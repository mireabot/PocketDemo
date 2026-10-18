module PackageBot
  class Logger
    def initialize(verbose: false)
      @verbose = verbose
    end

    def info(message)
      puts message
    end

    def verbose(message)
      puts message if @verbose
    end

    def error(message)
      puts "❌ #{message}"
    end

    def warn(message)
      puts "⚠️  #{message}"
    end

    def success(message)
      puts "✅ #{message}"
    end
    
    def section_header(message)
      info("\e[1;34m=== #{message} ===\e[0m")
    end

    def blank_line
      puts
    end
  end

  # Global logger instance
  LOGGER = Logger.new(verbose: ENV['VERBOSE'] == 'true')
end 