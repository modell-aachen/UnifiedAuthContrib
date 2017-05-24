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
    var vm = new Vue({
        el: "#userRegistration",
        methods: {
            openUserRegistration(showUserLoginName) {
                self = this;
                var o = {
                    contentComponent: { name: "user-create-component", propsData: {showUserLoginName: showUserLoginName}},
                    header: {
                    }
                };

                sidebar.showContent(o);
            }
        }
    });
});
