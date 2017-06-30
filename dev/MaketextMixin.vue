<script>
/*global foswiki*/
export default {
    methods: {
        // maketext(string, [arg1,arg2])
        maketext: function(text, params) {
            var args = ['UnifiedAuth', text];
            if(typeof params !== 'undefined' && params.length > 0) {
                args = args.concat(params);
            }
            return foswiki.jsi18n.get.apply(null, args);
        }
    }
}
</script>
