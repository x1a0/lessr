Fs     = require 'fs'
Path   = require 'path'
{exec} = require 'child_process'
Less   = require 'less'

exports.watch = (source, opts) ->
    SOURCES     = []
    NOT_SOURCES = {}
    OUTPUT      = opts?.output ? null
    ROOT        = Path.normalize source

    # Compile a path, which could be a file or a directory. If a directory is passed,
    # recursively compile all .less files in it and all subdirectories.
    compilePath = (source, is_root) ->
        Fs.stat source, (err, stats) ->
            throw err if err and err.code isnt "ENOENT"
            if err?.code is "ENOENT"
                console.error "File not found: #{source}"
                process.exit 1

            if stats.isDirectory()
                watchDir source
                Fs.readdir source, (err, files) ->
                    throw err if err and err.code isnt "ENOENT"
                    return if err?.code is "ENOENT"

                    index = SOURCES.indexOf source
                    files = files.filter (file) -> not hidden file
                    SOURCES[index..index] = (Path.join source, file for file in files)

                    files.forEach (file) ->
                        compilePath (Path.join source, file), no

            else if is_root or isLess source
                watchFile source
                compileLess source

            else
                NOT_SOURCES[source] = yes
                removeSource source

    # Compile a .less file.
    compileLess = (source) ->
        errHandler = (err) ->
            throw err if err and err.code isnt "ENOENT"
            console.log err

        Fs.readFile source, (err, code) ->
            errHandler err if err
            Less.render code.toString(), (err, css) ->
                return errHandler err if err

                css_path = outputPath source
                css_dir = Path.dirname css_path

                writeCss = ->
                    Fs.writeFile css_path, css, (err) ->
                        return errHandler err if err
                        console.log "compiled #{source}"

                # make sure dir tree exists
                Fs.exists css_dir, (exists) ->
                    if exists then writeCss() else exec "mkdir -p #{css_dir}", writeCss

    # Watch a single file and re-compile it.
    watchFile = (source) ->
        prev_stats = null
        compile_timer = null

        errHandler = (e) ->
            if e.code is "ENOENT"
                # The file could be removed, if it's not in SOURCES then simply return.
                # Otherwise give it another chance by rewatch(), if it fails then remove
                # the source.
                return if SOURCES.indexOf(source) is -1
                try
                    rewatch()
                    compile()
                catch e
                    throw e if e.code isnt "ENOENT"
                    removeSource source, yes
            else throw e

        compile = ->
            clearTimeout compile_timer
            compile_timer = wait 25, ->
                Fs.stat source, (err, stats) ->
                    return errHandler err if err
                    return rewatch() if prev_stats and stats.size is prev_stats.size and stats.mtime.getTime() is prev_stats.mtime.getTime()
                    prev_stats = stats
                    compileLess source
                    rewatch()

        try
            watcher = Fs.watch source, compile
        catch e
            errHandler e

        rewatch = ->
            watcher?.close()
            watcher = Fs.watch source, compile


    # Watch a directory of files for new additions.
    watchDir = (dir) ->
        timer = null
        try
            watcher = Fs.watch dir, ->
                clearTimeout timer
                timer = wait 25, ->
                    Fs.readdir dir, (err, files) ->
                        if err
                            throw err unless err.code is "ENOENT"
                            watcher.close()
                            return unwatchDir dir

                        for file in files when not hidden(file) and not NOT_SOURCES[file]
                            file = Path.join dir, file
                            continue if SOURCES.some (s) -> s.indexOf(file) >= 0
                            SOURCES.push file
                            compilePath file, no

        catch e
            throw e unless e.code is "ENOENT"

    # Remove source files in SOURCES that are under given dir.
    unwatchDir = (dir) ->
        prev_sources = SOURCES[..]
        to_remove = (file for file in SOURCES when file.indexOf(dir) >= 0)
        removeSource file, yes for file in to_remove

    # Remove given source file in SOURCES.
    # Remove corresponding compiled css file if `removeCss` is True.
    removeSource = (source, removeCss) ->
        index = SOURCES.indexOf source
        SOURCES.splice index, 1

        if removeCss
            css_path = outputPath source
            Fs.exists css_path, (exists) ->
                return if not exists
                Fs.unlink css_path, (err) ->
                    throw err if err and err.code isnt "ENOENT"
                    console.log "removed #{source}"

    # Generate output css file's path.
    outputPath = (source) ->
        src_dir = Path.dirname source
        relative_dir = src_dir.substring ROOT.length
        dir = if OUTPUT then Path.join(OUTPUT, relative_dir) else src_dir
        Path.join(dir, Path.basename(source, ".less")) + ".css"

    # Helpers
    isLess  = (file) -> /\.less$/.test file
    hidden  = (file) -> /^\.|~$/.test file
    wait    = (milliseconds, func) -> setTimeout func, milliseconds
    endless = (milliseconds, func) -> setInterval func, milliseconds

    # kickoff
    compilePath source, yes
