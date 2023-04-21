class Athena::Dotenv::Exceptions::Path < RuntimeError
  def initialize(path : String | Path, cause : ::Exception? = nil)
    super "Unable to read the '#{path}' environment file.", cause
  end
end
