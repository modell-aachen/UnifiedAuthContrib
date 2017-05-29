<template>
    <td>{{status}}</td>
</template>

<script>
export default {
    props: ['doc','params'],
    computed: {
        status: function() {
            var value;
            if(this.params[0]){
                value = this.doc[this.params[0]];
            } else{
                return '';
            }
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
