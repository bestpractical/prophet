/*
 * JavaScript Pretty Date
 * Copyright (c) 2008 John Resig (jquery.com)
 * Licensed under the MIT license.
 * Downloaded from http://ejohn.org/files/pretty.js on 2009-01-22
 */

// Takes an ISO time and returns a string representing how
// long ago the date represents.
function prettyDate(time){
	var date = new Date((time || "").replace(/-/g,"/").replace(/[TZ]/g," "));
        var now = new Date();
        // Timezone offsets are in minutes
		var diff = (((now.getTime() + (now.getTimezoneOffset() * 60 * 1000)) - date.getTime()) / 1000);
		var day_diff = Math.floor(diff / 86400);
			
	if ( isNaN(day_diff) || day_diff < 0 || day_diff > 300 )
		return;
		
    // JRV 2009-01-26 - date thresholds changed	
	return day_diff == 0 && (
			diff < 60 && "just now" ||
			diff < 120 && "1 minute ago" ||
			diff < 3600 && Math.floor( diff / 60 ) + " minutes ago" ||
			diff < 7200 && "1 hour ago" ||
			diff < 86400 && Math.floor( diff / 3600 ) + " hours ago") ||
		day_diff == 1 && "Yesterday" ||
		day_diff < 13 && day_diff + " days ago" ||
		day_diff < 45 && Math.ceil( day_diff / 7 ) + " weeks ago" ||
        day_diff < 300 && Math.ceil(day_diff/30) + " months ago"
}

// If jQuery is included in the page, adds a jQuery plugin to handle it as well
if ( typeof jQuery != "undefined" ) {
	jQuery.fn.prettyDate = function(){
		return this.each(function(){
			var date = prettyDate(this.title);
			if ( date )
				jQuery(this).text( date );
		});
	};

    // Jesse Vincent added this function to let you prettify a div rather than
    // an HREF on 2009-01-26
    jQuery.fn.prettyDateTag = function(){
        return this.each(function(){
            var original_date = (this.title || this.innerHTML);
            var date = prettyDate(original_date);
             if (!date) return;
            jQuery(this).attr('title', original_date) ;
            jQuery(this).html('<span style="display: none">'+original_date+'</span>'+ date );
        });
    }

}
