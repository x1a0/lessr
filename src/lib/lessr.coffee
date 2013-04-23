Fs     = require 'fs'
Path   = require 'path'
{exec} = require 'child_process'
Less   = require 'less'

SOURCES     = []
NOT_SOURCES = {}
OUTPUT      = null
ROOT        = null

exports.watch = (source, opts) ->
    OUTPUT = opts.output if opts?.output?
    ROOT   = Path.normalize source
    compilePath source, yes

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
            Fs.readFile source, (err, code) ->
                throw err if err and err.code isnt "ENOENT"
                return if err?.code is "ENOENT"
                compileLess source, code.toString()

        else
            NOT_SOURCES[source] = yes
            removeSource source

compileLess = (source, code) ->
    errHandler = (err) ->
        console.log err


    Less.render code, (err, css) ->
        return errHandler if err

        css_path = outputPath source
        css_dir = Path.dirname css_path

        writeCss = ->
            Fs.writeFile css_path, css, (err) ->
                return errHandler if err
                console.log "compiled #{source}"

        # make sure dir tree exists
        Fs.exists css_dir, (exists) ->
            if exists then writeCss() else exec "mkdir -p #{css_dir}", writeCss

watchFile = (source) ->
    prev_stats = null
    compile_timer = null

    errHandler = (e) ->
        if e.code is "ENOENT"
            return if SOURCES.indexOf(source) is -1
            try
                rewatch()
                compile()
            catch e
                removeSource source, yes
        else throw e

    compile = ->
        clearTimeout compile_timer
        compile_timer = wait 25, ->
            Fs.stat source, (err, stats) ->
                return errHandler err if err
                return rewatch() if prev_stats and stats.size is prev_stats.size and stats.mtime.getTime() is prev_stats.mtime.getTime()
                prev_stats = stats
                Fs.readFile source, (err, code) ->
                    return errHandler if err
                    compileLess source, code.toString()
                    rewatch()

    try
        watcher = Fs.watch source, compile
    catch e
        errHandler e

    rewatch = ->
        watcher?.close()
        watcher = Fs.watch source, compile


# watch a directory of files for new additions
watchDir = (source) ->
    timer = null
    try
        watcher = Fs.watch source, ->
            clearTimeout timer
            timer = wait 25, ->
                Fs.readdir source, (err, files) ->
                    if err
                        throw err unless err.code is "ENOENT"
                        watcher.close()
                        return unwatchDir source

                    for file in files when not hidden(file) and not NOT_SOURCES[file]
                        file = Path.join source, file
                        continue if SOURCES.some (s) -> s.indexOf(file) >= 0
                        SOURCES.push file
                        compilePath file, no

    catch e
        throw e unless e.code is "ENOENT"

unwatchDir = (source) ->
    prev_sources = SOURCES[..]
    to_remove = (file for file in SOURCES when file.indexOf(source) >= 0)
    removeSource file, yes for file in to_remove

removeSource = (source, removeCss) ->
    index = SOURCES.indexOf source
    SOURCES.splice index, 1

    if removeCss
        css_path = outputPath source
        Fs.exists css_path, (exists) ->
            if exists
                Fs.unlink css_path, (err) ->
                    throw err if err and err.code isnt "ENOENT"
                    console.log "removed #{source}"

outputPath = (source) ->
    src_dir = Path.dirname source
    relative_dir = src_dir.substring ROOT.length
    dir = if OUTPUT then Path.join(OUTPUT, relative_dir) else src_dir
    Path.join(dir, Path.basename(source, ".less")) + ".css"

isLess = (file) -> /\.less$/.test file
hidden = (file) -> /^\.|~$/.test file

wait = (milliseconds, func) -> setTimeout func, milliseconds
endless = (milliseconds, func) -> setInterval func, milliseconds
