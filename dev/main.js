/* global window $ Vue sidebar SearchGridPlugin */

import UserSelectorAddon from "./UserSelectorAddon";
import GroupSelectorAddon from "./GroupSelectorAddon";
import StatusField from "./StatusField";
import UserViewComponent from "./UserViewComponent";
import UserCreateComponent from "./UserCreateComponent";
import GroupViewComponent from "./GroupViewComponent";
import GroupCreateComponent from "./GroupCreateComponent";
import MaketextMixin from './MaketextMixin';

SearchGridPlugin.registerComponent("UserSelector", UserSelectorAddon);
SearchGridPlugin.registerComponent("GroupSelector", GroupSelectorAddon);
SearchGridPlugin.registerField("StatusField", StatusField);

Vue.component("UserViewComponent", UserViewComponent);
Vue.component("UserCreateComponent", UserCreateComponent);
Vue.component("GroupViewComponent", GroupViewComponent);
Vue.component("GroupCreateComponent", GroupCreateComponent);
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

Vue.component("GroupRegistration", {
    mixins: [MaketextMixin],
    template: '<button v-on:click="openGroupRegistration()" class="primary button">{{maketext("Create new group")}}</button>',
    methods: {
        openGroupRegistration() {
            var o = {
                contentComponent: { name: "group-create-component"},
                header: {
                }
            };
            sidebar.showContent(o);
        }
    }
});
$(function(){
    Vue.instantiateEach("#userRegistration", {});
    Vue.instantiateEach("#groupRegistration", {});
});
