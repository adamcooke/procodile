require 'spec_helper'
require 'procodile/config'

describe Procodile::Config do

  context "an application with a Procfile" do
    subject(:config) { Procodile::Config.new(File.join(APPS_ROOT, 'basic'))}

    it "should have a default environment" do
      expect(config.environment).to eq 'production'
    end

    it "should have a default procfile path" do
      expect(config.procfile_path).to eq File.join(APPS_ROOT, 'basic', 'Procfile')
    end

    it "should not have any options" do
      expect(config.options).to be_a Hash
      expect(config.options).to be_empty
    end

    it "should not have any local options" do
      expect(config.local_options).to be_a Hash
      expect(config.local_options).to be_empty
    end

    it "should have a determined options path" do
      expect(config.options_path).to eq File.join(APPS_ROOT, 'basic', 'Procfile.options')
    end

    it "should have a determined local options path" do
      expect(config.local_options_path).to eq File.join(APPS_ROOT, 'basic', 'Procfile.local')
    end

    it "should have a determined pid root" do
      expect(config.pid_root).to eq File.join(APPS_ROOT, 'basic', 'pids')
    end

    it "should have a determined log file" do
      expect(config.log_path).to eq File.join(APPS_ROOT, 'basic', 'procodile.log')
    end

    it "should not have a log root" do
      expect(config.log_root).to be_nil
    end

    it "should have a socket path" do
      expect(config.sock_path).to eq File.join(APPS_ROOT, 'basic', 'pids', 'procodile.sock')
    end

    it "should have a supervisor pid path" do
      expect(config.supervisor_pid_path).to eq File.join(APPS_ROOT, 'basic', 'pids', 'procodile.pid')
    end

    context "the process list" do
      subject(:process_list) { config.processes }

      it "should be a hash" do
        expect(process_list).to be_a Hash
      end

      context "a created process" do
        subject(:process) { config.processes['web'] }

        it "should be a process object" do
          expect(process).to be_a Procodile::Process
        end

        it "should have a suitable command" do
          expect(process.command).to eq "ruby process.rb web"
        end

        it "should have a log color" do
          expect(process.log_color).to_not be_nil
          expect(process.log_color).to eq 35
        end
      end
    end
  end

  context "an application without a Procfile" do
    subject(:config) { Procodile::Config.new(File.join(APPS_ROOT, 'empty'))}

    it "should raise an error" do
      expect { config }.to raise_error(Procodile::Error, /procfile not found/i)
    end
  end

  context "an application with options" do
    subject(:config) { Procodile::Config.new(File.join(APPS_ROOT, 'full')) }

    it "should have options" do
      expect(config.options).to_not be_empty
    end
    it "should return the app name" do
      expect(config.app_name).to eq 'specapp'
    end

    it "should return a custom pid root" do
      expect(config.pid_root).to eq File.join(APPS_ROOT, 'full', 'tmp/pids')
    end

    it "should have the socket in the custom pid root" do
      expect(config.sock_path).to eq File.join(APPS_ROOT, 'full', 'tmp/pids/procodile.sock')
    end

    it "should have the supervisor pid in the custom pid root" do
      expect(config.supervisor_pid_path).to eq File.join(APPS_ROOT, 'full', 'tmp/pids/procodile.pid')
    end

    it "should have environment variables" do
      expect(config.environment_variables).to be_a Hash
      expect(config.environment_variables['FRUIT']).to eq 'apple'
    end

    it "should flatten environment variables that have environment variants" do
      expect(config.environment_variables['VEGETABLE']).to eq 'potato'
    end

    it "should a custom log path" do
      expect(config.log_path).to eq File.join(APPS_ROOT, 'full', 'procodile.production.log')
    end

    it "should return a console command" do
      expect(config.console_command).to eq "irb -Ilib"
    end

    it "should be able to return options for a process" do
      expect(config.options_for_process('proc1')).to be_a Hash
      expect(config.options_for_process('proc1')['quantity']).to eq 2
      expect(config.options_for_process('proc1')['restart_mode']).to eq 'term-start'
      expect(config.options_for_process('proc2')).to be_a Hash
      expect(config.options_for_process('proc2')).to be_empty
    end

    context "with a different environment" do
      subject(:config) { Procodile::Config.new(File.join(APPS_ROOT, 'full'), 'development')}

      it "should return the correct environment variables" do
        expect(config.environment_variables['FRUIT']).to eq 'apple'
        expect(config.environment_variables['VEGETABLE']).to eq 'mushroom'
      end

      it "should return the correct log path" do
        expect(config.log_path).to eq File.join(APPS_ROOT, 'full', 'procodile.development.log')
      end
    end
  end

  context "reloading configuration" do
    subject(:config) { Procodile::Config.new(File.join(APPS_ROOT, 'full'))}

    it "should add missing processes" do
      expect(config.process_list.size).to eq 4
      change_procfile(config) { |opts| opts['proc5'] = 'ruby process.rb' }
      expect { config.reload }.to_not raise_error
      expect(config.process_list.size).to eq 5
      expect(config.process_list['proc5']).to eq 'ruby process.rb'
    end

    it "should remove removed processes" do
      expect(config.process_list.size).to eq 4
      change_procfile(config) { |opts| opts.delete('proc4') }
      expect { config.reload }.to_not raise_error
      expect(config.process_list.size).to eq 3
      expect(config.process_list['proc4']).to be_nil
    end

    it "should update existing processes" do
      expect(config.process_list['proc4']).to eq 'ruby process.rb'
      change_procfile(config) { |opts| opts['proc4'] = 'ruby process2.rb' }
      expect { config.reload }.to_not raise_error
      expect(config.process_list['proc4']).to eq 'ruby process2.rb'
    end

    it "should update processes when options change" do
      expect(config.options_for_process('proc1')['restart_mode']).to eq 'term-start'
      change_options(config) { |opts| opts['processes']['proc1']['restart_mode'] = 'usr2' }
      expect { config.reload }.to_not raise_error
      expect(config.options_for_process('proc1')['restart_mode']).to eq 'usr2'
    end
  end

end
