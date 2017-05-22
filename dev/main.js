/* global Vue moment window $ VueJSPlugin */

import UserSelectorAddon from "./UserSelectorAddon";
import StatusField from "./StatusField";
import UserViewComponent from "./UserViewComponent";
import UserCreateComponent from "./UserCreateComponent";

SearchGridPlugin.registerComponent("UserSelector", UserSelectorAddon);
SearchGridPlugin.registerField("StatusField", StatusField);

Vue.component("UserViewComponent", UserViewComponent);
Vue.component("UserCreateComponent", UserCreateComponent);

$(function(){
    new Vue({
        el: "#userRegistration",
        methods: {
            openUserRegistration() {
                var o = {
        contentComponent: { name: "user-create-component", propsData: {}},
        header: {
        },
        footer: {
          right: [
            {
              type: 'button',
              color: 'alert',
              text: 'Close sidebar',
              callback: function() {sidebar.hide();}
            }
          ]
        }
      };

      sidebar.showContent(o);
            }
        }
    });
});