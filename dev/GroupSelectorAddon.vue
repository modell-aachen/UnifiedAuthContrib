<template>
    <div style="display: none;">I add group selection functionality!</div>
</template>

<script>
/* global jsi18n sidebar */
import MaketextMixin from './MaketextMixin.vue'

export default {
    mixins: [MaketextMixin],
    props: ['api'],
    created: function(){
      this.api.registerEntryClickHandler(function(doc){
        let groupObject = {
          id: doc.cuid_s,
          displayName: doc.groupname_s,
          providerModule: doc.mainproviderdescription_s,
          providerid: doc.providerid_i,
          members: [],
          activemembers: doc.activemembers_i
        };

        if(doc.memberids_lst){
          for(let i = 0; i < doc.memberids_lst.length; i++){
            groupObject.members.push({
              id: doc.memberids_lst[i],
              loginName: doc.memberloginnames_lst[i],
              displayName: doc.memberdisplaynames_lst[i],
            });
          }
        }

        let leftLabels = [];
        for(let i = 0;  i < doc.providers_lst.length; i++){
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
          },
          footer: {
            right: [{
                type: 'button',
                color: 'secondary',
                text: jsi18n.get('UnifiedAuth', 'Close'),
                callback: function() {sidebar.hide();}
            }]
          }
      };

      sidebar.showContent(o);
    });
  }
}
</script>
