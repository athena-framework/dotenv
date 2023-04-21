class Athena::Dotenv; end

require "./exceptions/*"

class Athena::Dotenv
  VERSION = "0.1.0"

  private VARNAME_REGEX = /[A-Z][A-Z0-9_]*+/i

  private enum State
    VARNAME
    VALUE
  end

  getter prod_envs : Set(String) = Set{"prod"}

  @path : String | ::Path = ""
  @data = ""
  @values = Hash(String, String).new
  @reader : Char::Reader

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
  end

  private def create_format_exception(message : String) : Athena::Dotenv::Exceptions::Format
    line_pos = 0
    line_idx = 0
    line = nil

    @data.each_line do |line|
      line_pos += line.size

      if line_pos > @reader.pos
        line = line_idx
        break
      end

      line_idx += 1
    end

    # If `line` is still `nil`, the error would be on the last line.
    line = line || line_idx

    Athena::Dotenv::Exceptions::Format.new(
      message,
      Athena::Dotenv::Exceptions::Format::Context.new(
        @data,
        @path,
        line,
        @reader.pos
      )
    )
  end

  private def lex_varname : String
    unless match = /(export[ \t]++)?(#{VARNAME_REGEX})/.match(@data, @reader.pos, Regex::MatchOptions[:anchored])
      raise "Invalid character in variable name"
    end

    self.advance_reader match[0]

    if !@reader.has_next? || @reader.current_char.in? '\n', '#'
      raise "Unable to unset an environment variable" if match[1]?
      raise "Missing = in the environment variable declaration"
    end

    if @reader.current_char.whitespace?
      raise "Whitespace characters are not supported after the variable name"
    end

    if '=' != @reader.current_char
      raise "Missing = in the environment variable declaration"
    end

    # @reader.pos += 1

    match[2]
  end

  private def lex_value : String
    if match = (/[ \t]*+(?:#.*)?$/m).match(@data, @reader.pos, Regex::MatchOptions[:anchored])
      self.advance_reader match[0]
      self.skip_empty_lines

      return ""
    end

    if @reader.current_char.whitespace?
      raise "Whitespace characters are not supported after the variable name"
    end

    loaded_vars = ENV.fetch("ATHENA_DOTENV_VARS", "").split(',').to_set
    loaded_vars.delete ""
    v = ""

    loop do
      case char = @reader.current_char
      when '\''
        len = 0

        pp @reader.take_while { |c| c != '\'' }
      when '"'
      else
        value = ""
        previous_char = char
        char = @reader.next_char
        while @reader.has_next? && !char.in?('\n', '"', '\'') && !((previous_char.in?(' ', '\t')) && '#' == char)
          value += (previous_char = char)

          char = @reader.next_char
        end

        value = value.strip
        resolved_value = value
        resolved_value = self.resolve_variables resolved_value, loaded_vars
        resolved_value = self.resolve_commands resolved_value, loaded_vars
        # gsub `\\\\` with `\\`?

        if resolved_value == value && value.each_char.any? &.whitespace?
          raise self.create_format_exception "A value containing spaces must be surrounded by quotes"
        end

        v += resolved_value

        if !@reader.has_next? && '#' == char
          break
        end
      end

      break if !@reader.has_next? || @reader.current_char == '\n'
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
    value
  end

  private def resolve_variables(value : String, loaded_vars : Set(String)) : String
    value
  end

  private def skip_empty_lines : Nil
    while @reader.current_char.whitespace?
      @reader.next_char
    end
  end
end
