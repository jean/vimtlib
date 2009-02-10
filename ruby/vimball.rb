#!/usr/bin/env ruby
# vimball.rb
# @Author:      Thomas Link (micathom AT gmail com)
# @License:     GPL (see http://www.gnu.org/licenses/gpl.txt)
# @Created:     2009-02-10.
# @Last Change: 2009-02-10.
#
# This script creates and installs vimballs without vim.
#
# Before actually using this script, you might want to run
#
#   vimball.rb --print-config
#
# and check the values. If they don't seem right, you can change them in 
# the configuration file (in YAML format).
#
# Known incompatibilities:
# - Vim's vimball silently converts windows line end markers to unix 
#   markers. This script won't -- unless you run it with Windows's ruby 
#   maybe.
#


require 'yaml'
require 'logger'
require 'optparse'
require 'pathname'
require 'zlib'


class Vimball

    VERSION = '1.0.60'

    class AppLog
        def initialize(output=$stdout)
            @output = output
            $logger = Logger.new(output)
            set_level
        end
    
        def set_level
            if $DEBUG
                $logger.level = Logger::DEBUG
            elsif $VERBOSE
                $logger.level = Logger::WARN
            else
                $logger.level = Logger::INFO
            end
        end
    end


    HEADER = <<HEADER
" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.
UseVimball
finish
HEADER

    def initialize(args)

        AppLog.new

        @opts = Hash.new

        @opts['vimfiles'] = catch(:ok) do
            throw :ok, ENV['VIMFILES'] if ENV['VIMFILES']
            ['.vim', 'vimfiles'].each do |dir|
                ['HOME', 'USERPROFILE', 'VIM'].each do |env|
                    pdir = ENV[env]
                    if pdir
                        vimfiles = File.join(pdir, dir)
                        throw :ok, vimfiles if File.directory?(vimfiles)
                    end
                end
            end
            nil
        end

        @opts['outdir'] = File.join(@opts['vimfiles'], 'vimballs')

        @opts['configfile'] = File.join(@opts['vimfiles'], 'vimballs', 'config.yml')

        @opts['compress'] = false

        @dry = false

        @configs = []
        read_config

        opts = OptionParser.new do |opts|
            opts.banner =  'Usage: vimball.rb [OPTIONS] [make|install] FILES ...'
            opts.separator ' '
            opts.separator 'vimball.rb is a free software with ABSOLUTELY NO WARRANTY under'
            opts.separator 'the terms of the GNU General Public License version 2 or newer.'
            opts.separator ' '
        
            opts.on('-b', '--vimfiles DIR', String, 'Vimfiles directory') do |value|
                @opts['vimfiles'] = value
            end

            opts.on('-c', '--config YAML', String, 'Config file') do |value|
                @opts['configfile'] = value
                read_config
            end

            opts.on('-d', '--dir DIR', String, 'Destination directory for vimballs') do |value|
                @opts['outdir'] = value
            end

            opts.on('-n', '--dry-run', 'Don\'t actually run any commands; just print them') do |bool|
                @dry = bool
            end

            opts.on('--print-config', 'Print the configuration and exit') do |bool|
                puts YAML.dump(@opts)
                exit
            end

            opts.on('-z', '--gzip', 'Save as vba.gz') do |value|
                @opts['compress'] = value
            end


            opts.separator ' '
            opts.separator 'Other Options:'
        
            opts.on('--debug', 'Show debug messages') do |v|
                $DEBUG   = true
                $VERBOSE = true
                @logger.set_level
            end
        
            opts.on('-v', '--verbose', 'Run verbosely') do |v|
                $VERBOSE = true
                @logger.set_level
            end

            opts.on('--version', 'Version number') do |bool|
                puts VERSION
                exit 1
            end
        
            opts.on_tail('-h', '--help', 'Show this message') do
                puts opts
                exit 1
            end
        end
        $logger.debug "command-line arguments: #{args}"

        @opts['files'] ||= []
        rest = opts.parse!(args)
        @opts['mode'] = rest.shift
        @opts['files'].concat(rest)

    end


    def run
        if ready?

            @opts['files'].each do |file|
                $logger.info(file)
                case @opts['mode']
                when 'make'
                    mkvimball(file)
                when 'install'
                    install(file)
                end
            end

        else
            exit 1
        end
    end


    def ready?

        unless @opts['vimfiles']
            $logger.fatal "Where are your vimfiles?"
            return false
        end

        unless ['make', 'install'].include?(@opts['mode'])
            $logger.fatal "Mode must be 'make' or 'install'"
            return false
        end

        # unless @opts['configfile']
        #     puts "Where is my config file?"
        #     return false
        # end

        if @opts['files'].empty?
            $logger.fatal "No input files"
            return false
        end

        return true

    end


    private

    def read_config
        file = @opts['configfile']
        until @configs.include?(file)
            @configs << file
            if File.readable?(file)
                $logger.info "Read configuration from #{file}"
                @opts.merge!(YAML.load_file(file))
                file = @opts['configfile']
                break
            end
        end
    end


    def mkvimball(recipe)
        
        vimball = [HEADER]

        files = File.readlines(recipe)
        files.each do |file|
            file = file.strip
            unless file.empty?
                filename = File.join(@opts['vimfiles'], file)
                content = File.readlines(filename)
                # content.each do |line|
                #     line.sub!(/(\r\n|\r)$/, "\n")
                # end

                filename = Pathname.new(filename).relative_path_from(Pathname.new(@opts['vimfiles'])).to_s
                filename.gsub!(/\\/, '/')

                rewrite = @opts['rewrite']
                if rewrite
                    rewrite.each do |(pattern, replacement)|
                        rx = Regexp.new(pattern)
                        filename.gsub!(rx, replacement)
                    end
                end

                vimball << "#{filename}	[[[1\n#{content.size}\n"
                vimball.concat(content)
            end
        end

        vbafile = File.join(@opts['outdir'], File.basename(recipe, '.recipe') + '.vba')
        ensure_dir_exists(File.dirname(vbafile))
        vimball = vimball.join

        if @opts['compress']
            vbafile += '.gz'
            $logger.info "Save as: #{vbafile}"
            unless @dry
                Zlib::GzipWriter.open(vbafile) do |gz|
                    gz.write(vimball)
                end
            end
        else
            $logger.info "Save as: #{vbafile}"
            unless @dry
                File.open(vbafile, 'w') do |io|
                    io.puts(vimball)
                end
            end
        end

    end


    def install(file)

        vimball = nil
        if file =~ /\.gz$/
            File.open(file) do |f|
                gzip = Zlib::GzipReader.new(f)
                vimball = gzip.readlines
            end
        else
            vimball = File.readlines(file)
        end

        header = vimball.shift(3).join
        if header != HEADER
            $logger.fatal "Not a vimball: #{file}"
            exit 5
        end

        $logger.info "Install #{file}"

        until vimball.empty?

            fileheader = vimball.shift
            nlines = vimball.shift.to_i
            m = /^(.*?)\t\[\[\[1$/.match(fileheader)
            if m and nlines > 0
                filename = File.join(@opts['outdir'], m[1])
                content = vimball.shift(nlines)

                ensure_dir_exists(File.dirname(filename))

                $logger.info "Write #{filename}"
                unless @dry
                    File.open(filename, 'w') do |io|
                        io.puts(content.join)
                    end
                end

            else
                $logger.fatal "Error when parsing vimball: #{file}"
                exit 5
            end

        end

    end


    def ensure_dir_exists(dir)
        unless @dry or File.exist?(dir) or dir.empty? or dir == '.'
            parent = File.dirname(dir)
            unless File.exist?(parent)
                ensure_dir_exists(parent)
            end
            $logger.info "mkdir #{dir}"
            Dir.mkdir(dir)
        end
    end

end


if __FILE__ == $0

    Vimball.new(ARGV).run

end


# Local Variables:
# revisionRx: VERSION\s\+=\s\+\'
# End:
