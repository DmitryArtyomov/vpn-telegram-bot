require_relative 'storage'

class Users
  attr_reader :admin, :users

  def initialize
    load
  end

  def permit(uid)
    users << uid
    store
    uid
  end

  def permitted?(uid)
    admin?(uid) || users.include?(uid)
  end

  def admin?(uid)
    admin == uid
  end

  private

  def load
    data = Storage.read('users')
    @users = data || []
    @admin = Storage.read('admin')
  end

  def store
    Storage.write('users', @users)
  end
end
