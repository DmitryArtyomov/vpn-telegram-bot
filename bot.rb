# frozen_string_literal: true

require 'telegram/bot'
require_relative 'lib/message_processor'
require_relative 'lib/config'

Telegram::Bot::Client.run(Config.token) do |bot|
  processor = MessageProcessor.new(bot)
  bot.listen do |message|
    processor.process(message)
  end
end
