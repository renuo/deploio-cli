# frozen_string_literal: true

module Deploio
  module Commands
    class Auth < Thor
      include SharedOptions

      namespace "auth"

      desc "login", "Authenticate with nctl"
      def login
        setup_options
        @nctl.auth_login
      end

      desc "logout", "Log out from nctl"
      def logout
        setup_options
        @nctl.auth_logout
        Output.success("Logged out successfully")
      end

      desc "whoami", "Show current user and organization"
      def whoami
        setup_options
        @nctl.auth_whoami
      end
    end
  end
end
