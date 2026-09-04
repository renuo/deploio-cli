# frozen_string_literal: true

module Deploio
  class DatabaseResolver
    attr_reader :nctl, :current_org

    def initialize(nctl_client:)
      @nctl = nctl_client
      @current_org = @nctl.current_org
    end

    def resolve(database_name: nil)
      if database_name
        return database_ref.new(
          database_name,
          available_databases: available_databases_hash
        )
      end

      raise Deploio::Error, "No database specified"
    end

    # Returns hash mapping database names -> { project_name:, database_name: }
    def available_databases_hash
      @available_databases_hash ||= begin
        hash = {}
        current_org = @nctl.current_org

        fetch_databases.each do |database|
          metadata = database["metadata"] || {}
          project_name = metadata["namespace"] || ""
          database_name = metadata["name"]
          full_name = "#{project_name}-#{database_name}"

          hash[full_name] = {
            project_name: project_name,
            database_name: database_name
          }

          # Also index by short name (without org prefix) for convenience
          if current_org && project_name.start_with?("#{current_org}-")
            project = project_name.delete_prefix("#{current_org}-")
            short_name = "#{project}-#{database_name}"

            hash[short_name] ||= {
              project_name: project_name,
              database_name: database_name
            }
          end
        end

        hash
      end
    rescue
      {}
    end

    def short_name_for(namespace, database_name)
      org = current_org

      if org && namespace.start_with?("#{org}-")
        project = namespace.delete_prefix("#{org}-")
        "#{project}-#{database_name}"
      else
        "#{namespace}-#{database_name}"
      end
    end

    private

    def fetch_databases
      raise NotImplementedError
    end

    def database_ref
      raise NotImplementedError
    end
  end

  class MsDatabaseResolver < DatabaseResolver
    private

    def fetch_databases
      nctl.get_all_ms_databases
    end

    def database_ref
      MsDatabaseRef
    end
  end

  class PgDatabaseResolver < DatabaseResolver
    private

    def fetch_databases
      nctl.get_all_pg_databases
    end

    def database_ref
      PgDatabaseRef
    end
  end
end
