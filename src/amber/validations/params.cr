module Amber::Validators

  # Holds a validation error message
  record Error, param : String, value : String | Nil, message : String

  # This struct holds the validation rules to be performed
  struct BaseRule
    getter predicate : (String -> Bool)
    getter field : String
    getter value : String?

    def initialize(field : String | Symbol, @msg : String?, &block : String -> Bool)
      @field = field.to_s
      @predicate = block
    end

    def apply(params : HTTP::Params)
      raise Exceptions::Validator::InvalidParam.new(@field) unless params.has_key? @field
      @value = params[@field]
      @predicate.call params[@field] unless @predicate.nil?
    end

    def error
      Error.new @field, @value, error_message
    end

    def error_message
      @msg || "Field #{@field.to_s} is required"
    end
  end

  record ValidationBuilder, _validator : Params do
    def required(param : String | Symbol, msg : String? = nil)
      _validator.add_rule BaseRule.new(param, msg)
    end

    def required(param : String | Symbol, msg : String? = nil, &b : String -> Bool)
      _validator.add_rule BaseRule.new(param, msg, &b)
    end
  end

  class Params
    getter raw_params : HTTP::Params = HTTP::Params.parse("t=t")
    getter errors = [] of Error
    getter rules = [] of BaseRule
    getter params = {} of String => String | Nil

    def initialize(@raw_params : HTTP::Params); end

    # This will allow params to respond to HTTP::Params methods.
    # For example: [], []?, add, delete, each, fetch, etc.
    forward_missing_to @raw_params

    # Setups validation rules to be performed
    #
    # ```crystal
    # params.validation do
    #   required(:email) { |p| p.url? }
    #   required(:age, UInt32)
    # end
    # ```
    def validation
      with ValidationBuilder.new(self) yield
      self
    end

    # Input must be valid otherwise raises error, if valid returns a hash
    # of validated params Otherwise raises a Validator::ValidationFailed error
    # messages contain errors.
    #
    # ```crystal
    # user = User.new params.validate!
    # ```
    def validate!
      return params if valid?
      raise Amber::Exceptions::Validator::ValidationFailed.new errors
    end

    # Returns True or false wether the validation passed
    #
    # ```crystal
    # unless params.valid?
    #   response.puts {errors: params.errors}.to_json
    #   response.status_code 400
    # end
    # ```
    def valid?
      @errors.clear
      @params.clear

      @rules.each do |rule|
        unless rule.apply(raw_params)
          @errors << rule.error
        end

        @params[rule.field] = rule.value
      end

      errors.empty?
    end

    # Validates each field with a given set of predicates returns true if the
    # field is valid otherwise returns false
    #
    # ```crystal
    # required(:email) { |p| p.email? & p.size.between? 1..10 }
    # ```
    def add_rule(rule : BaseRule)
      @rules << rule
    end
  end
end
