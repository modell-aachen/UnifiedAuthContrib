<template>
    <div style="display: none;">I add user selection functionality!</div>
</template>

<script>
/* global jsi18n sidebar $ foswiki */
import MaketextMixin from './MaketextMixin.vue'

var makeToast = function(type, msg, closetime) {
    sidebar.makeToast({
        closetime: closetime || 5000,
        color: type,
        text: jsi18n.get("UnifiedAuth", msg)
    });
};
export default {
    mixins: [MaketextMixin],
    props: ['api'],
    created: function(){
      var self = this;
      this.api.registerEntryClickHandler(function(doc){
        var userObject = {
          id: doc.cuid_s,
          providerModule: doc.mainprovidermodule_s,
          displayName: doc.displayname_s,
          wikiName: doc.wikiname_s,
          email: doc.email_s,
          groups: [],
          deactivated: !!doc.deactivated_i
        };

        if(doc.groupids_lst){
          for(var i = 0; i < doc.groupids_lst.length; i++){
            userObject.groups.push({
              id: doc.groupids_lst[i],
              name: doc.groupnames_lst[i],
              provider: doc.groupproviders_lst[i]
            });
          }
        }

        var leftLabels = [];
        for(var j = 0;  j < doc.providers_lst.length; j++){
          leftLabels.push({
            type: 'label',
            color: 'secondary',
            text: doc.providers_lst[j]
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
              text: jsi18n.get('UnifiedAuth', (userObject.deactivated ? 'Activate' : 'Deactivate') + ' user'),
              callback: () => {
                var cuid = sidebar.$vm.contentComponent.propsData.user.id;
                var dn = sidebar.$vm.contentComponent.propsData.user.displayName;
                var deactivated = sidebar.$vm.contentComponent.propsData.user.deactivated;

                var toggle = () => {
                  sidebar.makeModal({type: 'spinner'});

                  $.ajax({
                    url: foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'toggleUserState'),
                    method: 'POST',
                    data: {cuid: cuid},
                    cache: false
                  }).done(
                    (data) => {
                      var response = JSON.parse(data);
                      sidebar.$vm.contentComponent.propsData.user.deactivated = response.deactivated;
                      var msg = 'User ' + (response.deactivated ? 'deactivated' : 'activated');
                      makeToast.call(self, 'success', msg, 3000);
                    }
                  ).fail(
                    (xhr) => makeToast.call(self, 'alert', JSON.parse(xhr.responseText).msg, 3000)
                  ).always(sidebar.hideModal);
                };

                var title = self.maketext((deactivated ? 'Activate' : 'Deactivate') + ' user');
                sidebar.makeModal({
                  title: title,
                  content: self.maketext(
                    deactivated ? 'Activate access to [_1] for user [_2]?' : "By deactivating the access to [_1] user [_2] won't be able to sign in anymore.",
                    [foswiki.getPreference('WIKITOOLNAME') || 'Q.wiki', dn]
                  ),
                  buttons: {
                    cancel: {
                      text: self.maketext("Abort"),
                      callback: sidebar.hideModal
                    },
                    confirm: {
                      text: title,
                      callback: () => Vue.nextTick(toggle)
                    }
                  }
                });
              }
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
                                      var params = {
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
                                      sidebar.makeModal({
                                          type: 'spinner'
                                      });
                                      $.post(foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'updateEmail'), params)
                                      .done(() => {
                                          sidebar.hideModal();
                                          makeToast.call(self, 'success', "Email address changed");
                                          sidebar.$vm.contentComponent.propsData.user.email = params.email;
                                          sidebar.hideModal();
                                      })
                                      .fail((xhr) => {
                                          sidebar.hideModal();
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
