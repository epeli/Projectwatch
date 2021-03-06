
path = require "path"
fs = require "fs"
{ EventEmitter } = require 'events'
{exec} = require "child_process"
watch = require "watch"

gex = require "gex"
walker = require "walker"
iniparser = require "iniparser"

webserver = require __dirname + "/web/server"
prompt = require __dirname + "/prompt"

class Watcher extends EventEmitter

  constructor: (@name, @cwd, @settings) ->
    super

    console.log "Found watch '#{ @name }' from #{ @cwd }/projectwatch.cfg"

    if @settings["error.stdout"]?
      @stdoutError = new RegExp @settings["error.stdout"]

    if @settings["error.stderr"]?
      @stderrTest = new RegExp @settings["error.stderr"]

    @id = @idfy @name

    @settings.glob ||= "*"
    @settings.watchdir ||= "."
    @settings.interval ||= 0

    if @settings.watchdir.substr(0,1) isnt "/"
      @settings.watchdir = path.join(@cwd, @settings.watchdir)

    @lastRunTimeStamp = 0
    @rerun = false
    @running = false
    @timer = null
    @exitstatus = 0
    @status = "start"

  idfy: (name) ->
    # Goofy iding function. Removes bad stuff from name. Nowjs dies if there is
    # dots in path etc. This should be enough unique. If not, user has way too
    # similar task names :P
    safename = name.replace(/[^a-zA-z]/g, "").toLowerCase()


  resetOutputs: ->
    @stdout = ""
    @stderr = ""
    @stdboth = ""


  start: ->

    watch.createMonitor @settings.watchdir, (monitor) =>


      monitor.on "created", (file) => @onModified(file)
      monitor.on "changed", (file) => @onModified(file)

  emitStatus: (status) ->
    @status = status
    @emit "status", @status

  matches: (filepath) ->
    for match in @settings.glob.split(" ")
      if gex(match).on path.basename filepath
        return true
    false

  delayedRun: (filepath) ->
    if not @timer
      console.log "Setting timer", @name
      @timer = setTimeout =>
        console.log "Manual run from timer", @name
        @onModified filepath, true
        @timer = null
      , @settings.interval * 60 * 1000


  hasTimeoutPassed: ->
    timeSinceLastrun = ((new Date()).getTime() - @lastRunTimeStamp) / 1000 / 60
    timeSinceLastrun > @settings.interval

  onModified: (filepath, manual=false) ->

    if not manual
      return unless @matches filepath
      if not @hasTimeoutPassed()
        console.log "Cannot run #{ @name } yet, time out has not passed"
        @delayedRun filepath
        return
    else
      console.log "#{ @name } got change on #{ filepath }"

    # Oh we are already running. Just request restart for this change.
    if @running
      console.log "Marking #{ @name } for rerun because because it is already running"
      @emitStatus "rerun"
      @rerun = true
    else
      @runCMD()



  runCMD: ->
    console.log "Running #{ @name }"

    @resetOutputs()
    @running = true
    @emitStatus "running"
    @lastRunTimeStamp = (new Date()).getTime()
    cmd = exec @settings.cmd,  cwd: @cwd, (err) =>
      @running = false

      @exitstatus = 0

      if err
        @exitstatus = err.code
      # Fake exitstatus if user supplied testers fail
      else if @stdoutError and @stdoutError.test @stdout
        @exitstatus = 1
      else if @stderrTest and @stderrTest.test @stderr
        @exitstatus = 1

      if @exitstatus isnt 0
        @emitStatus "error"

        prompt.setColor "red"
        console.log "Failed to run #{ @name }"
        prompt.resetColor()

      else
        @emitStatus "success"
        prompt.setColor "green"
        console.log "Ran", @name, "successfully! "
        prompt.resetColor()
        @exitstatus = 0




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



exports.searchAndWatch = (dirs, options) ->
    dirs.push process.cwd() unless dirs.length

    console.log "Searching projectwatch.cfg files from #{ dirs }\n"

    for searchDir in dirs
      finder = walker searchDir
      finder.on "file", (filepath) ->
        if path.basename(filepath) is "projectwatch.cfg"
            iniparser.parse filepath, (err, settingsObs) ->
              throw err if err
              for name, settings of settingsObs
                watcher = new Watcher name, path.dirname(filepath), settings
                watcher.start()
                watcher.runCMD()

                webserver.registerWatcher watcher

    webserver.start(options.port, options.host)

