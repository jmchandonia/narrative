/**
 * KBase widget to download content.
 */
(function($, undefined) {
    return KBWidget({
        name: 'DownloadFileWidget',
        version: '1.0.0',
        options: {
            data: null,
            name: null
        },
        init: function(options) {
            this._super(options);
            return this.render();
        },
        render: function() {
            // creater main comtainer
            var main = $('<div>');
            // add download button
            if ((this.options.data !== null) && (this.options.name !== null)) {
                var filedata = this.options.data;
                var filename = this.options.name;
                var downloadFn = function (data, filename) {
                    try {
                        data = window.btoa(data);
                    } catch (err) {
                    	var utftext = "";
                    	for (var n=0; n<data.length; n++) {
                            var c=data.charCodeAt(n);
                    	    if (c<128) {
                    		    utftext += String.fromCharCode(c);
                            } else if ((c>127) && (c<2048)) {
                                utftext += String.fromCharCode((c>>6)|192);
                                utftext += String.fromCharCode((c&63)|128);
                    		} else {
                    		    utftext += String.fromCharCode((c>>12)|224);
                                utftext += String.fromCharCode(((c>>6)&63)|128);
                                utftext += String.fromCharCode((c&63)|128);
                            }
                        }
                    	data = window.btoa(utftext);
                    }
                    data = 'data:application/octet-stream;base64,'+data;
                    var anchor = document.createElement('a');
                    anchor.setAttribute('download', filename);
                    anchor.setAttribute('href', data);
                    document.body.appendChild(anchor);
                    anchor.click();
                    document.body.removeChild(anchor);
                };
                main.append($('<button>')
                    .addClass('btn btn-link')
                    .text(filename)
                    .on('click', function () {
                        downloadFn(filedata, filename);
                    })
                );
            } else {
                main.append($('<p>').text("Error: file content is empty."));
            }
            // put container in cell
            this.$elem.append(main);
            return this;
        }
    });
})(jQuery);