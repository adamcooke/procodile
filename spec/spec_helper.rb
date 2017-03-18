require 'procodile'

module ProcodileHelpers
  def change_procfile(config, &block)
    new_procfile = YAML.load_file(config.procfile_path)
    block.call(new_procfile)
    allow(config).to receive(:load_process_list_from_file).and_return(new_procfile)
  end

  def change_options(config, &block)
    new_procfile = YAML.load_file(config.options_path)
    block.call(new_procfile)
    allow(config).to receive(:load_options_from_file).and_return(new_procfile)
  end
end

APPS_ROOT = File.expand_path('../apps', __FILE__)
RSpec.configure do |config|
  config.color = true
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.include ProcodileHelpers
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
