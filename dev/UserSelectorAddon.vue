<template>
    <div style="display: none;">I add user selection functionality!</div>
</template>

<script>
export default {
    props: ['api'],
    created: function(){
      this.api.registerEntryClickHandler(function(doc){
        let userObject = {
          id: doc.cuid_s,
          displayName: doc.displayname_s,
          wikiName: doc.wikiname_s,
          email: doc.email_s,
          groups: []
        };

        if(doc.groupids_lst){
          for(let i = 0; i < doc.groupids_lst.length; i++){
            userObject.groups.push({
              id: doc.groupids_lst[i],
              name: doc.groupnames_lst[i],
              provider: doc.groupproviders_lst[i]
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

        leftLabels.push({
          type: 'label',
          color: doc.deactivated_i == 0 ? 'success' : 'alert',
          text: jsi18n.get('UnifiedAuth', doc.deactivated_i == 0 ? 'Active' : 'Deactivated'),
        });

        var o = {
          content: JSON.stringify(doc),
          contentComponent: { name: "user-view-component", propsData: {user: userObject}},
          header: {
            left: leftLabels,
            right: [{
              type: 'button',
              color: 'primary',
              text: jsi18n.get('UnifiedAuth', 'Deactivate user'),
              callback: () => {}
            }, {
              type: 'dropdown',
              color: 'primary',
              tooltip: jsi18n.get('UnifiedAuth', 'more'),
              entries: [
                {
                  text: jsi18n.get('UnifiedAuth', 'Reset password'),
                  callback: () => console.log('Clicked entry 1')
                },
                {
                  text: jsi18n.get('UnifiedAuth', 'Change email address'),
                  callback: () => console.log('Clicked entry 2')
                },
                {
                  text: jsi18n.get('UnifiedAuth', 'Link user accounts'),
                  callback: () => console.log('Clicked entry 3')
                },
              ]
            }]
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
