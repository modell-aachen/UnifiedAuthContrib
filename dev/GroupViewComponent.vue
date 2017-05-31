<template>
    <div>
        <span class="section-title">{{group.displayName}}</span>
        <span v-html="maketext('Add user or group to the <b>[_1]</b>', group.displayName)"></span>
        <ua-entity-selector user group multiple ref="userSelector"></ua-entity-selector>
        <button class="primary button small pull-right" @click="addUserToGroup">{{maketext('Add user/ group')}}</button>

        <br/>
        <span class="section-title">{{maketext("All contained groups")}}</span>
        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{maketext('Name')}}</th><th>{{maketext('Source')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="member in group.members">
                <td :title="member.displayName">{{member.displayName}}</td>
                <td :title="member.provider"></td>
                <td :title="maketext('Remove user from group')"><i @click="removeUserFromGroup(member)" class="fa fa-trash fa-2x click" aria-hidden="true"></i></td>
            </tr>
        </tbody>
        </table>
        <br/>
        <span class="section-title">{{maketext("All contained users")}}</span>
        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{maketext('Name')}}</th><th>{{maketext('Group')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="member in group.members">
                <td :title="member.displayName">{{member.displayName}}</td>
                <td :title="member.provider"></td>
                <td :title="maketext('Remove user from group')"><i @click="removeUserFromGroup(member)" class="fa fa-trash fa-2x click" aria-hidden="true"></i></td>
            </tr>
        </tbody>
        </table>
    </div>
</template>

<script>
/* global sidebar $ foswiki */
import MaketextMixin from './MaketextMixin.vue'
import UaEntitySelector from './UaEntitySelector';

var makeToast = function(type, msg) {
    sidebar.makeToast({
        closetime: 5000,
        color: type,
        text: this.maketext(msg)
    });
};
export default {
    mixins: [MaketextMixin],
    props: ['propsData'],
    components: {
        UaEntitySelector
    },
    computed: {
        group(){
            if(this.propsData){
                return this.propsData.group;
            }
        }
    },
    methods: {
        addUserToGroup() {
            let selectedValues = this.$refs.groupSelector.getSelectedValues();
            let self = this
            let params = {
                cuid: this.user.id,
                group: selectedValues[0],
                wikiName: this.user.wikiName
            }
            sidebar.makeModal({
                type: 'spinner'
            });
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/addUsersToGroup", params)
            .done(() => {
                sidebar.hideModal();
                makeToast.call(self, 'success', this.maketext("Add User to Group successfull"));
                self.user.groups.push({name: selectedValues[0].name, provider: ''});
                self.$refs.groupSelector.clearSelectedValues();
            })
            .fail((xhr) => {
                sidebar.hideModal();
                var response = JSON.parse(xhr.responseText);
                makeToast.call(self, 'alert', response.msg);
            })
        },
        removeUserFromGroup(group) {
            let self = this
            let params = {
                cuids: this.user.id,
                group: group.name,
                wikiName: this.user.wikiName
            }
            sidebar.makeModal({
                type: 'spinner'
            });
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/removeUserFromGroup", params)
            .done(() => {
                sidebar.hideModal();
                makeToast.call(self, 'success', this.maketext("Removed User from Group successfull"));
                let index = self.user.groups.indexOf(group);
                self.user.groups.splice(index, 1);
            })
            .fail((xhr) => {
                sidebar.hideModal();
                var response = JSON.parse(xhr.responseText);
                makeToast.call(self, 'alert', response.msg);
            })
        }
    }
}
</script>

<style lang="sass">
.ma-data-table tr {
    th:first-child,
    td:first-child, {
        width: 225px;
        max-width: 225px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
}
i.click:hover{
    color: #525960;
}
.columns.title {
    color: #97938b;
}
</style>
