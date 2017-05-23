<template>
    <td>{{status}}</td>
</template>

<script>
export default {
    props: ['doc','params'],
    computed: {
        status: function() {
            var value = this.doc[this.params[0]];
            if(value == 0){
                return foswiki.jsi18n.get('UnifiedAuth',"Active");
            }
            else{
                return foswiki.jsi18n.get('UnifiedAuth',"Deactivated");
            }
        }
    }
}
</script>
