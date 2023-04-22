class Athena::Dotenv; end

require "./exceptions/*"

class Athena::Dotenv
  VERSION = "0.1.0"

  private VARNAME_REGEX = /(?i:[A-Z][A-Z0-9_]*+)/

  private enum State
    VARNAME
    VALUE
  end

  getter prod_envs : Set(String) = Set{"prod"}

  @path : String | ::Path = ""
  @data = ""
  @values = Hash(String, String).new
  @reader : Char::Reader
  @line_number = 1

  def initialize(
    @env_key : String = "APP_ENV",
    @debug_key : String = "APP_DEBUG"
  )
    # Can't use a `getter!` macro since that would return a copy of the reader each time :/
    @reader = uninitialized Char::Reader
  end

  def load(*paths : String | ::Path) : Nil
    self.load false, paths
  end

  def parse(data : String, path : String = ".env") : Hash(String, String)
    @path = path
    @data = data.gsub("\r\n", "\n").gsub("\r", "\n")
    @reader = Char::Reader.new @data.not_nil!

    @values.clear

    state : State = :varname
    name = ""

    self.skip_empty_lines

    while @reader.has_next?
      case state
      in .varname?
        name = self.lex_varname
        state = :value
      in .value?
        @values[name] = self.lex_value
        state = :varname
      end
    end

    if state.value?
      @values[name] = ""
    end

    begin
      @values.dup
    ensure
      @values.clear
      @reader = uninitialized Char::Reader
    end
  end

  def populate(values : Hash(String, String), override_existing_vars : Bool = false) : Nil
    update_loaded_vars = false

    loaded_vars = ENV.fetch("ATHENA_DOTENV_VARS", "").split(',').to_set

    values.each do |name, value|
      if !loaded_vars.includes?(name) && !override_existing_vars && ENV.has_key?(name)
        next
      end

      ENV[name] = value

      if !loaded_vars.includes?(name)
        loaded_vars << name
        update_loaded_vars = true
      end
    end

    if update_loaded_vars
      loaded_vars.delete ""
      ENV["ATHENA_DOTENV_VARS"] = loaded_vars.join ','
    end
  end

  def prod_envs(*envs : String) : self
    self.prod_envs envs
  end

  def prod_envs(prod_envs : Enumerable(String)) : self
    @prod_envs = prod_envs.to_set

    self
  end

  private def advance_reader(string : String) : Nil
    @reader.pos += string.size
    @line_number += string.count '\n'
  end

  private def create_format_exception(message : String) : Athena::Dotenv::Exceptions::Format
    Athena::Dotenv::Exceptions::Format.new(
      message,
      Athena::Dotenv::Exceptions::Format::Context.new(
        @data,
        @path,
        @line_number,
        @reader.pos
      )
    )
  end

  private def lex_nested_expression : String
    char = @reader.next_char
    value = ""

    until char.in? '\n', ')'
      value += char

      if '(' == char
        value += "#{self.lex_nested_expression})"
      end

      char = @reader.next_char

      unless @reader.has_next?
        raise self.create_format_exception "Missing closing parenthesis"
      end
    end

    if '\n' == char
      raise self.create_format_exception "Missing closing parenthesis"
    end

    value
  end

  private def lex_varname : String
    unless match = /(export[ \t]++)?(#{VARNAME_REGEX})/.match(@data, @reader.pos, Regex::MatchOptions[:anchored])
      raise self.create_format_exception "Invalid character in variable name"
    end

    self.advance_reader match[0]

    if !@reader.has_next? || @reader.current_char.in? '\n', '#'
      raise self.create_format_exception "Unable to unset an environment variable" if match[1]?
      raise self.create_format_exception "Missing = in the environment variable declaration"
    end

    if @reader.current_char.whitespace?
      raise self.create_format_exception "Whitespace characters are not supported after the variable name"
    end

    if '=' != @reader.current_char
      raise self.create_format_exception "Missing = in the environment variable declaration"
    end

    @reader.pos += 1

    match[2]
  end

  private def lex_value : String
    if match = (/[ \t]*+(?:#.*)?$/m).match(@data, @reader.pos, Regex::MatchOptions[:anchored])
      self.advance_reader match[0]
      self.skip_empty_lines

      return ""
    end

    if @reader.current_char.whitespace?
      raise self.create_format_exception "Whitespace is not supported before the value"
    end

    loaded_vars = ENV.fetch("ATHENA_DOTENV_VARS", "").split(',').to_set
    loaded_vars.delete ""
    v = ""

    loop do
      case char = @reader.current_char
      when '\''
        len = 0

        loop do
          if @reader.pos + (len += 1) == @data.size
            @reader.pos += len

            raise self.create_format_exception "Missing quote to end the value"
          end

          break if @data[@reader.pos + len] == '\''
        end

        v += @data[1 + @reader.pos, len - 1]
        @reader.pos += 1 + len
      when '"'
        value = ""

        char = @reader.next_char

        unless @reader.has_next?
          raise self.create_format_exception "Missing quote to end the value"
        end

        while '"' != char || ('\\' == @data[@reader.pos - 1] && '\\' != @data[@reader.pos - 2])
          value += char

          char = @reader.next_char

          unless @reader.has_next?
            raise self.create_format_exception "Missing quote to end the value"
          end
        end

        @reader.next_char
        value = value.gsub(%(\\"), '"').gsub("\\r", "\r").gsub("\\n", "\n")
        resolved_value = value
        resolved_value = self.resolve_variables resolved_value, loaded_vars
        resolved_value = self.resolve_commands resolved_value, loaded_vars
        resolved_value = resolved_value.gsub "\\\\", "\\"

        v += resolved_value
      else
        value = ""
        previous_char = @reader.previous_char
        char = @reader.next_char
        while @reader.has_next? && !char.in?('\n', '"', '\'') && !((previous_char.in?(' ', '\t')) && '#' == char)
          if '\\' == char && @reader.has_next? && @reader.peek_next_char.in? '\'', '"'
            char = @reader.next_char
          end

          value += (previous_char = char)

          if '$' == char && @reader.has_next? && '(' == @reader.peek_next_char
            @reader.next_char
            value += "(#{self.lex_nested_expression})"
          end

          char = @reader.next_char
        end

        value = value.strip

        resolved_value = value
        resolved_value = self.resolve_variables resolved_value, loaded_vars
        resolved_value = self.resolve_commands resolved_value, loaded_vars
        resolved_value = resolved_value.gsub "\\\\", "\\"

        if resolved_value == value && value.each_char.any? &.whitespace?
          raise self.create_format_exception "A value containing spaces must be surrounded by quotes"
        end

        v += resolved_value

        if @reader.has_next? && '#' == char
          break
        end
      end

      break unless @reader.has_next? && @reader.current_char != '\n'
    end

    self.skip_empty_lines

    v
  end

  private def load(override_existing_vars : Bool, paths : Enumerable(String | ::Path)) : Nil
    paths.each do |path|
      if !File.readable?(path) || File.directory?(path)
        raise Athena::Dotenv::Exceptions::Path.new path
      end

      self.populate(self.parse(File.read(path), path), override_existing_vars)
    end
  end

  private def resolve_commands(value : String, loaded_vars : Set(String)) : String
    return value unless value.includes? '$'

    regex = /
      (\\\\)?               # escaped with a backslash?
      \$
      (?<cmd>
          \(                # require opening parenthesis
          ([^()]|\g<cmd>)+  # allow any number of non-parens, or balanced parens (by nesting the <cmd> expression recursively)
          \)                # require closing paren
      )
    /x

    value.gsub regex do |_, match|
      if '\\' == match[1]
        next match[0][0, 1]
      end

      {% if flag? :win32 %}
        # TODO: Support windows?
        raise RuntimeError.new "Resolving commands is not supported on Windows."
      {% end %}

      process = ""
    end
  end

  private def resolve_variables(value : String, loaded_vars : Set(String)) : String
    return value unless value.includes? '$'

    regex = /
      (?<!\\)
      (?P<backslashes>\\*)             # escaped with a backslash?
      \$
      (?!\()                           # no opening parenthesis
      (?P<opening_brace>\{)?           # optional brace
      (?P<name>(?i:[A-Z][A-Z0-9_]*+))? # var name
      (?P<default_value>:[-=][^\}]++)? # optional default value
      (?P<closing_brace>\})?           # optional closing brace
    /x

    value.gsub regex do |_, match|
      if match["backslashes"].size.odd?
        next match[0][1..]
      end

      # Unescaped $ not followed by var name
      if match["name"]?.nil?
        next match[0]
      end

      if "{" == match["opening_brace"]? && match["closing_brace"]?.nil?
        raise self.create_format_exception "Unclosed braces on variable expansion"
      end

      name = match["name"]

      value = if loaded_vars.includes?(name) && @values.has_key?(name)
                @values[name]
              elsif @values.has_key? name
                @values[name]
              else
                ENV.fetch name, ""
              end

      if value.empty? && (default_value = match["default_value"]?.presence)
        if unsupported_char = default_value.each_char.find &.in?('\'', '"', '{', '$')
          raise self.create_format_exception "Unsupported character '#{unsupported_char}' found in the default value of variable '$#{name}'"
        end

        if '=' == match["default_value"][1]
          @values[name] = value
        end
      end

      if !match["opening_brace"]?.presence && !match["closing_brace"]?.nil?
        value += '}'
      end

      "#{match["backslashes"]}#{value}"
    end
  end

  private def skip_empty_lines : Nil
    if match = (/(?:\s*+(?:#[^\n]*+)?+)++/).match(@data, @reader.pos, Regex::MatchOptions[:anchored])
      self.advance_reader match[0]
    end
  end
end
