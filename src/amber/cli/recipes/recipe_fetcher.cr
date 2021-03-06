require "http/client"
require "zip"

module Amber::Recipes
  class RecipeFetcher
    getter kind : String # one of the supported kinds [app, model, controller, scaffold]
    getter name : String
    getter directory : String
    getter app_dir : String | Nil
    getter template_path : String

    def initialize(@kind : String, @name : String, @app_dir = nil)
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
      @template_path = "#{Dir.current}/.recipes/zip/#{@name}"
    end

    def fetch
      if Dir.exists?(@directory)
        return @directory
      end

      if Dir.exists?("#{@name}/#{@kind}")
        return "#{@name}/#{@kind}"
      end

      parts = @name.split("/")

      recipes_folder = @kind == "app" ? "#{app_dir}/.recipes" : "./.recipes"

      if parts.size == 2
        shard_name = parts[-1]

        if shard_name && @kind != "app"
          if Dir.exists?("#{recipes_folder}/lib/#{shard_name}/#{@kind}")
            return "#{recipes_folder}/lib/#{shard_name}/#{@kind}"
          end
          return nil
        end

        if shard_name && @kind == "app" && try_github
          fetch_github shard_name
          if Dir.exists?("#{recipes_folder}/lib/#{shard_name}/#{@kind}")
            return "#{recipes_folder}/lib/#{shard_name}/#{@kind}"
          end
        end
      end

      @template_path = "#{recipes_folder}/zip/#{@name}"

      if Dir.exists?("#{@template_path}/#{@kind}")
        return "#{@template_path}/#{@kind}"
      end

      if (name = @name) && name.downcase.starts_with?("http") && name.downcase.ends_with?(".zip")
        return fetch_zip name
      end

      return fetch_url
    end

    def try_github
      url = "https://raw.githubusercontent.com/#{@name}/master/shard.yml"

      HTTP::Client.get(url) do |response|
        if response.status_code == 200
          return true
        end
      end
      false
    end

    def create_recipe_shard(shard_name)
      dirname = "#{app_dir}/.recipes"
      Dir.mkdir_p(dirname)
      filename = "#{dirname}/shard.yml"

      yaml = {name: "recipe", version: "0.1.0", dependencies: {shard_name => {github: @name, branch: "master"}}}

      CLI.logger.info "Create Recipe shard #{filename}", "Generate", :light_cyan
      File.open(filename, "w") { |f| yaml.to_yaml(f) }
    end

    def fetch_github(shard_name)
      create_recipe_shard shard_name

      CLI.logger.info "Installing Recipe", "Generate", :light_cyan
      Amber::CLI::Helpers.run("cd #{app_dir}/.recipes && shards update")
    end

    def recipe_source
      CLI.config.recipe_source || "https://github.com/amberframework/recipes/releases/download/dist/"
    end

    def fetch_zip(url : String)
      # download the recipe zip file from the github repository
      HTTP::Client.get(url) do |response|
        if response.status_code == 302
          # download the recipe zip frile from redirected url
          if redirection_url = response.headers["Location"]?
            HTTP::Client.get(redirection_url) do |redirected_response|
              save_zip(redirected_response)
            end
          end
        elsif response.status_code != 200
          CLI.logger.error "Could not find the recipe #{@name} : #{response.status_code} #{response.status_message}", "Generate", :light_red
          return nil
        end

        save_zip(response)
      end
    end

    def save_zip(response : HTTP::Client::Response)
      Dir.mkdir_p(@template_path)

      Zip::Reader.open(response.body_io) do |zip|
        zip.each_entry do |entry|
          path = "#{@template_path}/#{entry.filename}"
          if entry.dir?
            Dir.mkdir_p(path)
          else
            File.write(path, entry.io.gets_to_end)
          end
        end
      end

      if Dir.exists?("#{@template_path}/#{@kind}")
        return "#{@template_path}/#{@kind}"
      end

      CLI.logger.error "Cannot generate #{@kind} from #{@name} recipe", "Generate", :light_red
      return nil
    end

    def fetch_url
      return fetch_zip "#{recipe_source}/#{@name}.zip"
    end
  end
end
