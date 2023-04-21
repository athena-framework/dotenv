class Athena::Dotenv::Exceptions::Format < RuntimeError
  struct Context
    getter path : String
    getter line_number : Int32

    def initialize(
      @data : String,
      path : ::Path | String,
      @line_number : Int32,
      @offset : Int32
    )
      @path = path.to_s
    end

    def details : String
      before = @data[Math.max(0, @offset - 20), Math.min(20, @offset)].gsub "\n", "\\n"
      after = @data[@offset, 20].gsub "\n", "\\n"

      %(...#{before}#{after}...\n#{" " * (before.size + 2)}^ line #{@line_number} offset #{@offset})
    end
  end

  getter context : Athena::Dotenv::Exceptions::Format::Context

  def initialize(message : String, @context : Athena::Dotenv::Exceptions::Format::Context, cause : ::Exception? = nil)
    super "#{message} in '#{@context.path}' at line #{@context.line_number}.\n#{@context.details}", cause
  end
end
