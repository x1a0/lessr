Fs     = require 'fs'
Path   = require 'path'
{exec} = require 'child_process'
Less   = require 'less'

exports.compile = (source, opts) ->
    SOURCES =
        compile: [] # .less files to be compiled
        watch:   [] # .less files to be watched
        ignore:  {} # files to be ignored
        base:    {} # remember base of each file to be compiled

    OUTPUT = opts?.output ? null
    OPTIONS =
        compress: opts?.compress ? no

    # Walk a path, which could be a file or a dir. If a dir is passed,
    # recursively compile all .less files in it and walk all sub dirs.
    walkPath = (path, type, base) ->
        Fs.stat path, (err, stats) ->

            # The path should always exist if passed to this method.
            # It's either given by user or detected by watching.
            if err?.code is "ENOENT"
                console.error "Path not found: #{path}"
                process.exit 1

            if stats.isDirectory()
                # If path is a dir, watch it for changing.
                watchDir path, type, base

                # Go through all items in the dir.
                Fs.readdir path, (err, files) ->
                    throw err if err and err.code isnt "ENOENT"
                    return if err?.code is "ENOENT"

                    # Filter out hidden files and dirs.
                    files = files.filter (file) -> not hidden file

                    # If current path can be found in corresponding sources set
                    # then it must be a dir added in previous walking. Replace it
                    # with items under it.
                    index = SOURCES[type].indexOf path
                    SOURCES[type][index..index] = (Path.join path, file for file in files)
                    SOURCES.base[path] = base if not SOURCES.base[path]?

                    # recursively walk on each child
                    walkPath Path.join(path, file), type, base for file in files

            else if isLess path
                # Add it to SOURCES if not yet (happens when it's the given source)
                SOURCES[type].push path if SOURCES[type].indexOf(path) is -1
                SOURCES.base[path] = base if not SOURCES.base[path]?

                # For a less file compile and watch it.
                watchFile path, type

                compileLess path if type is "compile"

            else
                # For a non less file add it to ignore set.
                SOURCES.ignore[path] = yes


    # Watch a dir for changing.
    watchDir = (dir, type, base) ->
        timer = null
        try
            watcher = Fs.watch dir, ->
                clearTimeout timer
                timer = wait 25, ->
                    Fs.readdir dir, (err, files) ->
                        if err
                            throw err unless err.code is "ENOENT"
                            # Dir is deleted.
                            watcher.close()
                            return unwatchDir dir, type

                        for file in files when not hidden(file) and not SOURCES.ignore[file]
                            path = Path.join dir, file

                            # Skip if the path or any sub-path is already in sources set.
                            continue if SOURCES[type].some (s) -> s.indexOf(path) >= 0

                            SOURCES[type].push path
                            SOURCES.base[path] = base if not SOURCES.base[path]?

                            walkPath path, type, base

        catch err
            throw err unless err.code? is "ENOENT"

    # Unwatch a dir. Remove files in SOURCES that are under given dir.
    unwatchDir = (dir, type) ->
        prev_sources = SOURCES[type][..]
        to_remove = (file for file in SOURCES[type] when file.indexOf(dir) >= 0)
        removeSource file, type for file in to_remove

    # Remove given source file in SOURCES. If it's removing a to-compile source
    # remove the corresponding compiled css file.
    removeSource = (path, type) ->
        index = SOURCES[type].indexOf path
        SOURCES[type].splice index, 1 if index >= 0
        base = SOURCES.base[path]
        delete SOURCES.base[path]

        if type is "compile"
            css_path = getCssPath path, base
            Fs.exists css_path, (exists) ->
                return if not exists
                Fs.unlink css_path, (err) ->
                    throw err if err and err.code isnt "ENOENT"
                    log "removed #{path}"

    # Watch a file for changing.
    watchFile = (path, type) ->
        prev_stats = null
        compile_timer = null

        errHandler = (err) ->
            if err.code is "ENOENT"
                # The file could be removed, if it's not in SOURCES then simply return.
                # Otherwise give it another try by rewatch(). If that fails too then
                # remove the source.
                return if SOURCES[type].indexOf(path) is -1

                try
                    rewatch()
                    compile()
                catch err
                    throw err unless err.code is "ENOENT"
                    removeSource path, type
            else throw err

        # Do the compiling.
        compile = ->
            clearTimeout compile_timer
            compile_timer = wait 25, ->
                Fs.stat path, (err, stats) ->
                    return errHandler err if err
                    return rewatch() if prev_stats and stats.size is prev_stats.size and stats.mtime.getTime() is prev_stats.mtime.getTime()

                    prev_stats = stats
                    compileLess path if type is "compile"
                    compileAll() if type is "watch"
                    rewatch()

        rewatch = ->
            watcher?.close()
            watcher = Fs.watch path, compile

        try
            rewatch()
        catch err
            errHandler err

    # Compile a .less file.
    compileLess = (path) ->
        errHandler = (err) ->
            return if err.code? is "ENOENT"
            throw err

        Fs.readFile path, (err, code) ->
            errHandler err if err

            # Specify search paths for @import directives in Less.
            opts =
                paths: [Path.dirname path]
                compress: OPTIONS.compress

            # Compile less.
            Less.render code.toString(), opts, (err, css) ->
                return errHandler err if err

                # Generate output path of current file.
                css_path = getCssPath path, SOURCES.base[path]
                css_dir  = Path.dirname css_path

                # Func to write css file.
                writeCss = ->
                    Fs.writeFile css_path, css, (err) ->
                        return errHandler err if err
                        log "compiled #{path}"

                # Make sure dir tree exists then write.
                Fs.exists css_dir, (exists) ->
                    if exists then writeCss() else exec "mkdir -p #{css_dir}", writeCss

    # Compile all .less files if need.
    compileAll = ->
        for file in SOURCES["compile"]
            compileLess file

    # Get path of an output CSS file. If there is no output base dir specified in options
    # then the compiled css file should sit next to the less file. Otherwise the css file
    # should be in the specified output location and keep the relative sub path.
    getCssPath = (path, base) ->
        src_dir = Path.dirname path
        out_dir = if OUTPUT then Path.join(OUTPUT, src_dir.substring base.length) else src_dir
        "#{Path.join out_dir, Path.basename(path, ".less")}.css"

    # Helpers
    hidden  = (path) -> /^\.|~$/.test path
    isLess  = (path) -> /\.less$/.test path
    wait    = (ms, func) -> setTimeout func, ms
    endless = (ms, func) -> setInterval func, ms

    log = (message) ->
        return if process.env.SLIENT?
        console.log "#{(new Date).toLocaleTimeString()} - #{message}"

    # kickoff
    source = [source] if typeof source is "string"
    for one in source
        walkPath one, "compile", Path.normalize(Path.dirname one)

    if opts?.watch?
        opts.watch = [opts.watch] if Object.prototype.toString.call(opts.watch) isnt "[object Array]"
        for one in opts.watch
            walkPath one, "watch", Path.normalize(Path.dirname one)

    @SOURCES = SOURCES
    return @
