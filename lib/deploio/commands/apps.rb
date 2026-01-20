# frozen_string_literal: true

module Deploio
  module Commands
    class Apps < Thor
      include SharedOptions

      namespace 'apps'

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'

      default_task :list

      desc 'list', 'List all apps'
      def list
        setup_options
        raw_apps = @nctl.get_all_apps

        if options[:json]
          puts JSON.pretty_generate(raw_apps)
          return
        end

        if raw_apps.empty?
          Output.warning('No apps found') unless merged_options[:dry_run]
          return
        end

        resolver = AppResolver.new(nctl_client: @nctl)

        rows = raw_apps.map do |app|
          metadata = app['metadata'] || {}
          spec = app['spec'] || {}
          for_provider = spec['forProvider'] || {}
          git = for_provider['git'] || {}
          config = for_provider['config'] || {}
          namespace = metadata['namespace'] || ''
          name = metadata['name'] || ''

          [
            resolver.short_name_for(namespace, name),
            project_from_namespace(namespace, resolver.current_org),
            presence(config['size'], default: 'micro'),
            presence(git['revision'])
          ]
        end

        Output.table(rows, headers: %w[APP PROJECT SIZE REVISION])
      end
      private

      def presence(value, default: '-')
        value.nil? || value.to_s.empty? ? default : value
      end

      def project_from_namespace(namespace, current_org)
        if current_org && namespace.start_with?("#{current_org}-")
          namespace.delete_prefix("#{current_org}-")
        else
          namespace
        end
      end
    end
  end
end
