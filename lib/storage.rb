require 'yaml/store'

class Storage
  def self.write(...)
    new.write(...)
  end

  def self.read(...)
    new.read(...)
  end

  def write(key, value)
    storage.transaction do
      storage[key] = value
    end
    value
  end

  def read(key)
    storage.transaction do
      storage[key]
    end
  end

  private

  def storage
    @storage ||= YAML::Store.new('data.storage')
  end
end
