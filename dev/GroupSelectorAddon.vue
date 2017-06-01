<template>
    <div style="display: none;">I add group selection functionality!</div>
</template>

<script>
/* global sidebar */
import MaketextMixin from './MaketextMixin.vue'

export default {
    mixins: [MaketextMixin],
    props: ['api'],
    created: function(){
        this.api.registerEntryClickHandler(function(doc){
            var groupObject = {
                id: doc.cuid_s,
                displayName: doc.groupname_s,
                providerModule: doc.mainproviderdescription_s,
                providerid: doc.providerid_i,
                members: JSON.parse(doc.members_json),
                activemembers: doc.activemembers_i
            };

            var leftLabels = [];
            for(var i = 0;  i < doc.providers_lst.length; i++){
                leftLabels.push({
                    type: 'label',
                    color: 'secondary',
                    text: doc.providers_lst[i]
                });
            }

            var o = {
                content: JSON.stringify(doc),
                contentComponent: { name: "group-view-component", propsData: {group: groupObject}},
                header: {
                    left: leftLabels,
                }
            };

            sidebar.showContent(o);
        });
    }
}
</script>
