Fs             = require 'fs'
Path           = require 'path'
{EventEmitter} = require 'events'
Watchr         = require 'watchr'
Less           = require 'less'
Async          = require 'async'
Mkdirp         = require 'mkdirp'

watch = (src, dst, opts, next) ->
    # opts is optional
    if not next?
        next = opts
        opts = {}

    Watchr.watch {
        path: src

        listeners:
            error: (err) ->
                console.log "An error occured: #{err}"

            watching: (err, instance, is_watching) ->
                if err
                    console.log "Failed watching `#{instance.path}` due ot #{err}"
                else
                    console.log "Started watching `#{instance.path}`"

            change: (type, path, curr, prev) ->
                return if Path.extname(path) isnt ".less"

                # get relative path
                path = path.replace src + Path.sep, ""
                switch type
                    when "create" then onCreate path, curr, finish
                    when "update" then onUpdate path, curr, prev, finish
                    when "delete" then onDelete path, prev, finish

        next: next
    }

    finish = (err) ->
        console.log err if err

    onCreate = (path, curr, done) ->
        onUpdate path, curr, null, done

    onUpdate = (path, curr, prev, done) ->
        Async.waterfall [
            (next) ->
                Fs.readFile Path.join(src, path), {encoding: "utf8"}, next

            (data, next) ->
                Less.render data, next

            # make sure dir tree exists
            (css, next) ->
                Mkdirp Path.join(dst, Path.dirname path), (err) ->
                    next err, css

            (css, next) ->
                Fs.writeFile Path.join(dst, "#{basename path}.css"), css, (err) ->
                    next err
        ], (err) ->
            done err

    onDelete = (path, prev, done) ->
        Fs.unlink Path.join(dst, "#{basename path}.css"), (err) ->
            done err

    # get rid of filename extension
    basename = (path) ->
        path[..(path.lastIndexOf ".") - 1]


module.exports = {watch}
