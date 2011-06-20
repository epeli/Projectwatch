
path = require "path"
fs = require "fs"
{ EventEmitter } = require 'events'
{exec} = require "child_process"

watch = require "watch"
gex = require "gex"
findit = require "findit"
iniparser = require "iniparser"


port = 5678

class Watcher extends EventEmitter

  constructor: (@name, @cwd, @settings) ->
    super

    @settings.glob ||= "*"
    @settings.watchdir ||= "."

    if @settings.watchdir.substr(0,1) isnt "/"
      @settings.watchdir = path.join(@cwd, @settings.watchdir)

    @rerun = false
    @running = false
    @exitstatus = 0



  resetOutputs: ->
    @stdout = ""
    @stderr = ""
    @stdboth = ""


  start: ->

    watch.createMonitor @settings.watchdir, (monitor) =>

      console.log "Found watch '#{ @name }' from directory #{ @settings.watchdir }"

      monitor.on "created", (file) => @onModified(file)
      monitor.on "changed", (file) => @onModified(file)

  onModified: (filepath, manual=false) ->

    if not manual
      for match in @settings.glob.split(" ")
        if gex(match).on path.basename filepath
          ok = true
          break
      return unless ok


    # Oh we are already running. Just request restart for this change.
    if @running
      @rerun = true
    else
      @runCMD()


    console.log "Change on '#{ filepath }' running '#{ @name }'!"

  runCMD: ->

    @resetOutputs()
    @emit "start"

    @running = true
    cmd = exec @settings.cmd,  cwd: @cwd, (err) =>
      @running = false

      if err
        id = @name.replace /[^a-zA-z]/g, ""
        console.log """Error in '#{ @name }'
          details http://localhost:#{ port }/##{ id }"""
        @exitstatus = err.code
      else
        console.log "\nRan", @name, "successfully!\n", (new Date) + 2*60*60
        @exitstatus = 0

      @emit "end", @exitstatus


      if @rerun
        # There has been a change(s) during this run. Let's rerun it.
        console.log "Rerunning '#{ @name }'"
        @rerun = false
        @runCMD()


    cmd.stdout.on "data", (data) =>
      @stdout += data.toString()
      @stdboth += data.toString()
      @emit "stdout", data.toString()
      @emit "stdboth", data.toString()

    cmd.stderr.on "data", (data) =>
      @stderr += data.toString()
      @stdboth += data.toString()
      @emit "stderr", data.toString()
      @emit "stdboth", data.toString()


webserver = require __dirname + "/web/server.coffee"

exports.run = ->

  dirs = process.argv.splice(2)
  dirs.push process.cwd() unless dirs.length

  console.log "Searching projectwatch.cfg files from #{ dirs }\n"

  for searchDir in dirs
    finder = findit.find(searchDir)
    finder.on "file", (filepath) ->
      if path.basename(filepath) is "projectwatch.cfg"
          iniparser.parse filepath, (err, settingsObs) ->
            throw err if err
            for name, settings of settingsObs
              watcher = new Watcher name, path.dirname(filepath), settings
              watcher.start()
              watcher.runCMD()

              webserver.registerWatcher watcher

  webserver.start(port)





