require_relative 'users'
require_relative 'config'

class MessageProcessor
  DAYS_TO_SECONDS = 24 * 60 * 60
  DATE_FORMAT = '%d-%m-%y %H:%M'.freeze

  attr_reader :bot, :api, :prefix, :users

  def initialize(bot)
    @bot = bot
    @api = @bot.api
    @prefix = Config.prefix
    @users = Users.new
  end

  def process(message)
    return unless permitted!(message)

    case message.text
    when '/start', '/help'
      help(message)
    when '/add'
      add(message)
    when %r{^/permanent \w+$}
      permanent(message)
    when '/list'
      list(message)
    when '/list_permanent'
      list_permanent(message)
    when %r{^/delete [\w\_\d]+$}
      delete(message)
    when %r{^/permit \d+$}
      permit(message)
    end
  end

  private

  # Message methods

  def help(message)
    text = <<~TEXT.strip
      Список команд:

      /start, /help - Отображение данного сообщения
      /add - Создание нового временного клиента (на #{Config.expiration_days} день/дней)
      /permanent `имя_клиента` - Создание нового постоянного клиента
      /list - Список всех временных клиентов
      /list\\_permanent - Список всех постоянных клиентов
    TEXT
    text += "\n" + <<~TEXT.strip if admin?(message)
      /delete `имя_клиента` - Удаление временного клиента
      /permit `id_телеграм` - Добавление нового пользователя бота
    TEXT

    send_message(message, text)
  end

  def add(message)
    client_name = "#{prefix}_#{Time.now.to_i}"
    `pivpn add -n #{client_name}`
    `echo "pivpn -r #{client_name} -y" | at now + #{Config.expiration_days} days`
    send_config(message, client_name)
  end

  def permanent(message)
    client_name = message.text.match(%r{^/permanent (\w+)$})[1]
    if File.exist?(file_name(client_name))
      send_message(message, "Клиент `#{client_name}` уже существует")
      return
    end
    `pivpn add -n #{client_name}`
    send_config(message, client_name)
    send_qr(message, client_name)
  end

  def delete(message)
    return unless admin!(message)

    client_name = message.text.match(%r{^/delete ([\w\_\d]+)$})[1]
    if File.exist?(file_name(client_name))
      `pivpn -r #{client_name} -y`
      send_message(message, "Клиент `#{client_name}` удалён")
    else
      send_message(message, "Клиент `#{client_name}` не найден")
    end
  end

  def permit(message)
    return unless admin!(message)

    user_id = message.text.match(%r{^/permit (\d+)$})[1]
    if user_id != user_id.to_i.to_s
      send_message(message, 'Неверный id пользователя')
    else
      users.permit(user_id.to_i)
      send_message(message, "Пользователь `#{user_id}` добавлен в разрешённые")
    end
  end

  def list(message)
    data = clients_table(:temporary)
    text = if data
             "Список временных клиентов (#{data.lines.count - 2}):\n\n```\n#{data}\n```"
           else
             'Клиенты не найдены'
           end
    send_message(message, text)
  end

  def list_permanent(message)
    data = clients_table(:permanent)
    text = if data
             "Список постоянных клиентов (#{data.lines.count - 2}):\n\n```\n#{data}\n```"
           else
             'Клиенты не найдены'
           end
    send_message(message, text)
  end

  # Other methods

  def send_config(message, client_name)
    api.send_document(chat_id: message.chat.id, document: Faraday::UploadIO.new(file_name(client_name), 'text/plain'))
  end

  def send_qr(message, client_name)
    png_file_name = "/tmp/#{client_name}.png"
    `qrencode -s 10 -o "#{png_file_name}" < "#{file_name(client_name)}"`
    api.send_photo(chat_id: message.chat.id, photo: Faraday::UploadIO.new(png_file_name, 'image/png'))
  end

  def send_message(message, text)
    api.send_message(chat_id: message.chat.id, text: text, parse_mode: 'Markdown')
  end

  def file_name(client_name)
    "/home/vpn/configs/#{client_name}.conf"
  end

  def existing_clients
    clients = { permanent: [], temporary: [] }
    File.read('/etc/wireguard/configs/clients.txt').split("\n").each do |line|
      client_name, _, created_at = line.split
      created_at = Time.at(created_at.to_i, in: Config.timezone)
      data = {
        name: client_name,
        created_at: created_at
      }
      if client_name =~ %r{^#{prefix}_\d+$}
        data[:expires_at] = created_at + Config.expiration_days * DAYS_TO_SECONDS
        clients[:temporary] << data
      else
        clients[:permanent] << data
      end
    end
    clients
  end

  def clients_table(type)
    clients = existing_clients[type]
    return if clients.empty?

    idx_length = clients.length.to_s.length
    name_length = if type == :permanent
                    clients.map { |client| client[:name].length }.max
                  else
                    clients.first[:name].length
                  end
    date_length = Time.now.strftime(DATE_FORMAT).length
    headers = [
      '№'.rjust(idx_length),
      spacer,
      'Имя'.center(name_length),
      spacer,
      (type == :temporary ? 'Истекает' : 'Создан').center(date_length)
    ].join('')
    table_spacers = [
      '━' * idx_length,
      '━╋━',
      '━' * name_length,
      '━╋━',
      '━' * date_length,
    ].join('')

    clients.map.with_index do |client, idx|
      [
        (idx + 1).to_s.rjust(idx_length),
        spacer,
        client[:name].ljust(name_length),
        spacer,
        client[type == :temporary ? :expires_at : :created_at].strftime(DATE_FORMAT)
      ].join('')
    end.unshift(table_spacers).unshift(headers).join("\n")
  end

  def spacer
    @spacer ||= ' ┃ '
  end

  def permitted!(message)
    permitted = permitted?(message)
    send_message(message, "У вас нет доступа к боту. Обратитесь к администратору") unless permitted
    permitted
  end

  def permitted?(message)
    users.permitted?(message.from.id)
  end

  def admin!(message)
    return false unless permitted?(message)

    admin = admin?(message)
    send_message(message, "У вас нет доступа к этой команде") unless admin
    admin
  end

  def admin?(message)
    users.admin?(message.from.id)
  end
end
