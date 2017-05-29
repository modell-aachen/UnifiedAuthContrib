<template>
    <div style="display: none;">I add user selection functionality!</div>
</template>

<script>
/* global jsi18n sidebar $ foswiki */
import MaketextMixin from './MaketextMixin.vue'

var makeToast = function(type, msg) {
    sidebar.makeToast({
        closetime: 5000,
        color: type,
        text: jsi18n.get("UnifiedAuth", msg)
    });
};
export default {
    mixins: [MaketextMixin],
    props: ['api'],
    created: function(){
      let self = this;
      this.api.registerEntryClickHandler(function(doc){
        let userObject = {
          id: doc.cuid_s,
          providerModule: doc.mainprovidermodule_s,
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
                  callback: () => {
                    sidebar.makeModal({
                        title: "Reset password",
                        content: "bla bla bla",
                        buttons: {
                            cancel: {
                                text: 'Abort',
                                callback: function() { sidebar.hideModal(); }
                            },
                            confirm: {
                                text: 'Reset password',
                                callback: function() {
                                    sidebar.hideModal();
                                }
                            },
                        }
                    });
                  }
                },
                {
                  text: jsi18n.get('UnifiedAuth', 'Change email address'),
                  callback: () => {
                      if(sidebar.$vm.contentComponent.propsData.user.providerModule != 'Topic') {
                          makeToast.call(self, 'alert', "Function only supported for topic provider");
                          return;
                      }
                      sidebar.makeModal({
                          title: self.maketext("Change Email address"),
                          content: self.maketext("You can use this form to change your registered e-mail address.") + " " + self.maketext("Currently known e-mail address") + ": <b>" +sidebar.$vm.contentComponent.propsData.user.email + '</b><input type="text" name="email" placeholder="' + self.maketext("New e-mail address") + '">',
                          buttons: {
                              cancel: {
                                  text: self.maketext("Abort"),
                                  callback: function() { sidebar.hideModal(); }
                              },
                              confirm: {
                                  text: self.maketext("Change Email address"),
                                  callback: function() {
                                      let params = {
                                          cuid: sidebar.$vm.contentComponent.propsData.user.id,
                                          email: document.getElementsByName("email")[0].value,
                                          wikiname: sidebar.$vm.contentComponent.propsData.user.wikiName
                                      }
                                      if (!params.email) {
                                          makeToast.call(self, 'alert', 'Field email is required');
                                          return false;
                                      }
                                      if (!/^(([^<>()\[\]\.,;:\s@\"]+(\.[^<>()\[\]\.,;:\s@\"]+)*)|(\".+\"))@(([^<>()[\]\.,;:\s@\"]+\.)+[^<>()[\]\.,;:\s@\"]{2,})$/i.test(params.email)) {
                                          makeToast.call(self, 'alert', 'Invalid email address');
                                          return false;
                                      }
                                      $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/updateEmail", params)
                                      .done(() => {
                                          makeToast.call(self, 'success', "Email address changed");
                                          sidebar.$vm.contentComponent.propsData.user.email = params.email;
                                          sidebar.hideModal();
                                      })
                                      .fail((xhr) => {
                                          var response = JSON.parse(xhr.responseText);
                                          makeToast.call(self, 'alert', response.msg);
                                      })
                                  }
                              },
                          }
                      });
                  }
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
