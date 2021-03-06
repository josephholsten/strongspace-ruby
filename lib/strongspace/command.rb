require 'strongspace/helpers'
require 'strongspace/plugin'
require 'strongspace/commands/base'

Dir["#{File.dirname(__FILE__)}/commands/*.rb"].each { |c| require c }

module Strongspace
  module Command
    class InvalidCommand < RuntimeError; end
    class CommandFailed  < RuntimeError; end

    extend Strongspace::Helpers

    class << self

      def run(command, args, retries=0)
        Strongspace::Plugin.load!
        begin
          run_internal 'auth:reauthorize', args.dup if retries > 0
          run_internal(command, args.dup)
        rescue InvalidCommand
          error "Unknown command. Run 'strongspace help' for usage information."
        rescue RestClient::Unauthorized
          if retries < 3
            STDERR.puts "Authentication failure"
            run(command, args, retries+1)
          else
            error "Authentication failure"
          end
        rescue RestClient::ResourceNotFound => e
          error extract_not_found(e.http_body)
        rescue RestClient::RequestFailed => e
          error extract_error(e.http_body) unless e.http_code == 402
        rescue RestClient::RequestTimeout
          error "API request timed out. Please try again, or contact support@strongspace.com if this issue persists."
        rescue CommandFailed => e
          error e.message
        rescue Interrupt => e
          error "\n[canceled]"
        end
      end

      def run_internal(command, args, strongspace=nil)
        klass, method = parse(command)
        runner = klass.new(args, strongspace)
        raise InvalidCommand unless runner.respond_to?(method)
        runner.send(method)
      end

      def parse(command)
        parts = command.split(':')
        case parts.size
          when 1
            begin
              return eval("Strongspace::Command::#{command.camelize}"), :index
            rescue NameError, NoMethodError
              return Strongspace::Command::Base, command.to_sym
            end
          else
            begin
              const = Strongspace::Command
              command = parts.pop
              parts.each { |part| const = const.const_get(part.camelize) }
              return const, command.to_sym
            rescue NameError
              raise InvalidCommand
            end
        end
      end

      def extract_not_found(body)
        body =~ /^[\w\s]+ not found$/ ? body : "Resource not found"
      end

      def extract_error(body)
        msg = parse_error_json(body) || 'Internal server error'
        msg.split("\n").map { |line| ' !   ' + line }.join("\n")
      end

      def parse_error_json(body)
        json = JSON.parse(body.to_s)
        json['status']
      rescue JSON::ParserError
      end
    end
  end
end
