require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/lograge/configuration/settings'
require 'ddtrace/contrib/lograge/patcher'

module Datadog
  module Contrib
    module Lograge
      # Description of Lograge integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.11.0')

        register_as :lograge

        def self.version
          Gem.loaded_specs['lograge'] && Gem.loaded_specs['lograge'].version
        end

        def self.loaded?
          !defined?(::Lograge).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Datadog::Contrib::Rails::Utils.railtie_supported?
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
