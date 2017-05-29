/* global window $ Vue sidebar SearchGridPlugin */

import UserSelectorAddon from "./UserSelectorAddon";
import StatusField from "./StatusField";
import UserViewComponent from "./UserViewComponent";
import UserCreateComponent from "./UserCreateComponent";
import MaketextMixin from './MaketextMixin';

SearchGridPlugin.registerComponent("UserSelector", UserSelectorAddon);
SearchGridPlugin.registerField("StatusField", StatusField);

Vue.component("UserViewComponent", UserViewComponent);
Vue.component("UserCreateComponent", UserCreateComponent);
Vue.component("UserRegistration", {
    mixins: [MaketextMixin],
    props: {
        showUserLoginname: {
            type: String
        }
    },
    template: '<button v-on:click="openUserRegistration()" class="primary button">{{maketext("Create new user")}}</button>',
    computed: {
        showLoginName() {
            if (this.showUserLoginname !== '1' && this.showUserLoginname !== '0') {
                return 0;
            }
            return parseInt(this.showUserLoginname);
        }
    },
    methods: {
        openUserRegistration() {
            var o = {
                contentComponent: { name: "user-create-component", propsData: {showUserLoginName: this.showLoginName}},
                header: {
                }
            };
            sidebar.showContent(o);
        }
    }
});

$(function(){
    new Vue({
        el: "#userRegistration",
    });
});
