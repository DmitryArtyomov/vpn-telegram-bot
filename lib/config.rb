require 'yaml'

class Config
  YAML.load_file(File.expand_path('../../config.yml', __FILE__)).each do |key, value|
    define_singleton_method(key) do
      value
    end
  end
end
