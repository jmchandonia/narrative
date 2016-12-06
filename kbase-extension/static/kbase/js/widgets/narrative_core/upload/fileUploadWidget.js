define([
    'jquery',
    'bluebird',
    'kbwidget',
    'narrativeConfig',
    'common/runtime',
    'dropzone',
    'handlebars',
    'text!kbase/templates/data_staging/dropzone_area.html',
    'text!kbase/templates/data_staging/dropped_file.html',
    'css!ext_components/dropzone/dist/dropzone.css',
], function(
    $,
    Promise,
    KBWidget,
    Config,
    Runtime,
    Dropzone,
    Handlebars,
    DropzoneAreaHtml,
    DropFileHtml
) {
    return new KBWidget({
        name: 'fileUploadWidget',

        init: function(options) {
            this._super(options);
            this.dropzoneTmpl = Handlebars.compile(DropzoneAreaHtml);
            this.dropFileTmpl = Handlebars.compile(DropFileHtml);
            this.path = options.path;
            this.ftpUrl = Config.url('ftp_api_url');
            this.userId = options.userId;
            this.render();
            return this;
        },

        render: function() {
            var $dropzoneElem = $(this.dropzoneTmpl({username: this.userId}));
            $dropzoneElem.find('#clear-completed > button').click(function(e) {
                e.preventDefault();
                e.stopPropagation();
                this.dropzone.removeAllFiles();
                $dropzoneElem.find('#clear-completed').css({'display': 'none'});
            }.bind(this));

            this.$elem.append($dropzoneElem);
            this.dropzone = new Dropzone($dropzoneElem.get(0), {
                url: this.ftpUrl + '/upload',
                accept: function(file, done) {
                    console.log('uploading ' + file.name + ' = ' + file.size + 'B');
                    done();
                },
                headers: {'Authorization': Runtime.make().authToken()},
                paramName: 'uploads',
                previewTemplate: this.dropFileTmpl(),
                autoProcessQueue: true,
                parallelUploads: 1
            })
            .on('totaluploadprogress', function(progress) {
                // $dropzoneElem.find('#total-progress .progress-bar').style.width = progress + '%';
            }.bind(this))
            .on('addedFile', function(file) {
                $dropzoneElem.find('#global-info').css({'display': 'inline'});
                $dropzoneElem.find('#upload-message').text(this.makeUploadMessage());
            }.bind(this))
            .on('uploadprogress', function(file, progress, bytesSent) {

            })
            .on('success', function(file, serverResponse) {
                $dropzoneElem.find('#clear-completed').css({'display': 'inline'});
                $dropzoneElem.find('#upload-message').text(this.makeUploadMessage());
                file.previewElement.querySelector('#status-message').textContent = 'Completed';
                file.previewElement.querySelector('.progress').style.display = 'none';
                file.previewElement.querySelector('#status-message').style.display = 'inline';
            }.bind(this))
            .on('sending', function(file) {
                $dropzoneElem.find('#global-info').css({'display': 'inline'});
                $dropzoneElem.find('#upload-message').text(this.makeUploadMessage());
            }.bind(this))
            .on('reset', function() {
                $dropzoneElem.find('#global-info').css({'display': 'none'});
            });


            // dz.on("sending", function(file) {
            //     // Show the total progress bar when upload starts
            //     // document.querySelector("#total-progress").style.opacity = "1";
            //     // And disable the start button
            //     file.previewElement.querySelector(".start").setAttribute("disabled", "disabled");
            // });
        },

        makeUploadMessage: function() {
            if (!this.dropzone) {
                return "No files uploading.";
            }
            var numUploading = this.dropzone.getUploadingFiles().length;
            var numQueued = this.dropzone.getQueuedFiles().length;
            if (numUploading === 0 && numQueued === 0) {
                return "No files uploading.";
            }
            return [
                "Uploading ",
                numUploading,
                " files (",
                numQueued,
                " queued) to ",
                this.getPath()
            ].join("");
        },

        setPath: function(path) {
            this.path = path;
            this.$elem.find('input[name="destPath"]').val(path);
        },

        getPath: function() {
            return this.path;
        },

    });
});
