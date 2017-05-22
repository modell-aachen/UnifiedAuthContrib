<template>
    <td><i v-bind:class="status" aria-hidden="true"></i></td>
</template>

<script>
export default {
    props: ['doc','params'],
    computed: {
        status: function() {
            var value = this.doc[this.params[0]];
            if(value == 0){
                return "fa fa-2x fa-check-circle";
            }
            else{
                return "fa fa-2x fa-times-circle";
            }
        }
    }
}
</script>