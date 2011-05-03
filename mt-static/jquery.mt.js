(function($){
    var defaults = {
        filter_title  : '#filter-title',
        filter_select : '#filter-select',
        selected      : null
    };
    var settings;
    var self;
    var methods = {
        // TODO - handle cancel properly to reset state
        setfilter : function( f, v ) {  
            return this.each( function() {
                self = $(this);
                self.find('#filter-col :selected').removeAttr('selected');
                self.find('#filter-col option[value='+f+']').attr('selected','selected');
                self.find('#filter-col').trigger('change');
                self.find('#'+f+'-val').val( v ).trigger('change');
            });
        },
        init : function( options ) {
            settings = $.extend( {}, defaults, options);
            return this.each( function() {
                self = $(this);
                
                // TODO - port over execFilter
                // TODO - bind keypress to text input fields
                // turn on and off the filter
                self.find('.filter-toggle').click( function() {
                    if ( self.find( settings.filter_title ).is(':visible') ) {
                        self.find( settings.filter_title ).hide();
                        self.find( settings.filter_select ).show();
                    } else {
                        self.find( settings.filter_title ).show();
                        self.find( settings.filter_select ).hide();
                    }
                });
                
                // dislpay fields for selected filter type
                self.find('#filter-col').change( function() {
                    if ( self.find(settings.filter_select).size() == 0 ) return;
                    $(this).parent().find('.shown').hide().removeClass('shown');
                    var value = $(this).val();
                    if ( value != 'none' ) {
                        var fltr = self.find('#filter-' + value);
                        fltr.show().addClass('shown');
                        if ( fltr.find(':selected').hasClass('search') ) self.find('#filter-button').hide();
                        var label = $(this).find(':selected').text();
                        self.find('#filter-text-col').html( '<strong>' + label + '</strong>');
                    }
                });
                
                // execute filter
                self.find('.filter-value').change( function() {
                    // This set the text value of the filter so that it is human readable.
                    if ( $(this).val() == '' && !$(this).find(':selected').hasClass('search') ) return;
                    if ( $(this).is('input') ) {
                        self.find('#filter-text-val').html( '<strong>' + $(this).val() + '</strong>' );
                    } else if ( $(this).is('select') ) {
                        var label = $(this).find(':selected').text();
                        self.find('#filter-text-val').html( '<strong>' + label + '</strong>' );
                        
                        // This makes the button visible or controls filter search function
                        var opt = $(this).find(':selected');
                        if ( $(this).hasClass('has-search') ) {
                            if ( opt.hasClass('search') ) { 
                                window.location = ScriptURI + opt.attr('value');
                            }
                            else {
                                if ( opt.attr('value') == '' ) {
                                    self.find('#filter-button').hide();
                                    return;
                                }
                            }
                        } else if ( $(this).attr('id') == 'filter-col' ) {
                            if (opt.attr('value') == 'author_id') {
                                if ( $('#author_id-val').find(':selected').attr('value') == "") {
                                    self.find('#filter-button').hide();
                                    return;
                                }
                            }
                        }
                    }
                    self.find('#filter-button').css('display','inline');
                });
                
            });
        }
    }; 
    $.fn.listfilter = function( method ) {
        // Method calling logic
        if ( methods[method] ) {
            return methods[ method ].apply( this, Array.prototype.slice.call( arguments, 1 ));
        } else if ( typeof method === 'object' || ! method ) {
            return methods.init.apply( this, arguments );
        } else {
            $.error( 'Method ' +  method + ' does not exist on jQuery.listfilter' );
        }    
    }
})(jQuery);

jQuery(document).ready( function($) {
    /* Filter/Listing Screen BEGIN */
    $('.listing-filter').listfilter({});
    /* Filter/Listing Screen END */

    /* Content Nav BEGIN */
    if ( $('.settings-screen #content-nav').length ) {
        // TODO - this code is only really relevant on the blog and system
        // settings pages. It could probably be modified further to only
        // initialize on those screens?
        var active = $('#content-nav ul li.active a').attr('title');
        $('#'+active).show();
        $('fieldset input, fieldset select, fieldset textarea').change( function () {
            var sel = '#content-nav ul li a[title="'+active+'"]';
            var e = $(sel).parent();
            if (!e.hasClass('changed')) { 
                e.find('b').html( e.find('b').html() + " *" );
            }
            e.addClass('changed');
        });
        $('#content-nav ul li a').click( function() {
            var current = $(this).parent().parent().find('.active');
            var newactive = $(this).attr('title');
            current.removeClass('active');
            $('#' + active).hide();
            $(this).parent().addClass('active');
            $('#' + newactive).show();
            active = newactive;
        });  
        $.history.init(function(hash){
            if (hash == "") hash = "about";
            $('#content-nav ul li.'+hash+'-tab a').click();
        });
    }
    /* Content Nav END */

    /* Dashboard BEGIN */
    $('.widget-close-link').click( function() {
        var w = $(this).parents('.widget');
        var id = w.attr('id');
        var label = w.find('.widget-label span').html();
        w.html('spinner - removing');
		$.post( ScriptURI, {
            '__mode'          : 'update_widget_prefs',
            'widget_id'       : id,
            'blog_id'         : BlogID,
            'magic_token'     : MagicToken,
            'widget_action'   : 'remove',
            'widget_scope'    : 'dashboard:' + (BlogID > 0 ? 'blog' : 'system') + ':' + BlogID,
            'return_args'     : '__mode=dashboard&amp;blog_id=' + BlogID,
            'json'            : 1,
            'widget_singular' : 1
        }, function(data, status, xhr) {
            w.fadeOut().remove();
            $('#add_widget').show();
            $('#add_widget').find('select').append('<option value="'+id+'">'+label+"</option>");
        },'json').error(function() { showMsg("Error removing widget.", "widget-updated", "alert"); });
    });
    $('#add_widget button').click( function() {
        var id = $(this).parent().find('select').val();
		$.post( ScriptURI, {
            '__mode'          : 'update_widget_prefs',
            'blog_id'         : BlogID,
            'magic_token'     : MagicToken,
            'widget_action'   : 'add',
            'widget_scope'    : 'dashboard:' + (BlogID > 0 ? 'blog' : 'system') + ':' + BlogID,
            'widget_set'      : $(this).parents('#add_widget').find('input[name=widget_set]').val(),
            'return_args'     : '__mode=dashboard&amp;blog_id=' + BlogID,
            'widget_id'       : id,
            'json'            : 1,
            'widget_singular' : 1
        }, function(data, status, xhr) {
            var trgt = '#widget-container-' + data['result']['widget_set'];
            var html = $( data['result']['widget_html'] ).css('visible','hidden');
            $(html).hide().appendTo(trgt).fadeIn('slow');
        },'json').error(function() { showMsg("Error removing widget.", "widget-updated", "alert"); });
    });
    /* Dashboard END */

    /* Dialogs BEGIN */
    $('.open-dialog').fancybox({
        'width'         : 660,
        'height'        : 498,
        'autoScale'     : false,
        'transitionIn'  : 'none',
        'transitionOut' : 'none',
        'type'          : 'iframe'
    });
    /* Dialogs END */

    /* Display Options BEGIN */
    jQuery('.display-options-link').click( function() {
        var opts = jQuery('#display-options-widget');
        if ( opts.hasClass('active') ) opts.removeClass( 'active' );
        else opts.addClass( 'active' );
    });
    /* Display Options END */

});