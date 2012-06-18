module Fluent
  class RedisCounterOutput < BufferedOutput
    Fluent::Plugin.register_output('redis_counter', self)
    attr_reader :host, :port, :db_number, :redis, :patterns

    def initialize
      super
      require 'redis'
      require 'msgpack'
    end

    def configure(conf)
      super
      @host = conf.has_key?('host') ? conf['host'] : 'localhost'
      @port = conf.has_key?('port') ? conf['port'].to_i : 6379
      @db_number = conf.has_key?('db_number') ? conf['db_number'].to_i : nil
      @patterns = []
      conf.elements.select { |e|
        e.name == 'pattern'
      }.each { |e|
        if e.has_key?('count_key') == false
          raise Fluent::ConfigError, '"count_key" is required.'
        end
        count_value = 1
        if e.has_key?('count_value')
          begin
            count_value = Integer(e['count_value'])
          rescue
            raise Fluent::ConfigError, 'invalid "count_value", integer required.'
          end
        end
        matches = {}
        e.each_key { |key|
          if key =~ /^match_/
            name = key['match_'.size .. key.size]
            matches[name] = e[key]
          end
        }
        @patterns << {
          'matches' => matches,
          'count_key' => e['count_key'],
          'count_value' => count_value
        }
      }
    end

    def start
      super
      @redis = Redis.new(
        :host => @host, :port => @port,
        :thread_safe => true, :db => @db_number
      )
    end

    def shutdown
      @redis.quit
    end

    def format(tag, time, record)
      record.to_msgpack
    end

    def write(chunk)
      table = {}
      table.default = 0
      chunk.open { |io|
        begin
          MessagePack::Unpacker.new(io).each { |record|
            record.each_key { |key|
              if (value = parseInt(record[key])) != 0
                table[key] += value
              end
            }
          }
        rescue EOFError
          # EOFError always occured when reached end of chunk.
        end
      }
      table.each_key { |key|
        if (value = table[key]) != 0
          @redis.incrby(key, value)
        end
      }
    end

    def parseInt(stringValue)
      begin
        Integer(stringValue)
      rescue ArgumentError
        0
      rescue TypeError
        0
      end
    end

  end
end
