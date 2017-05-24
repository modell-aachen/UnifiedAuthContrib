<template>
    <div>
        <span class="section-title">{{user.displayName}}</span>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">{{maketext('WikiName')}}:</div>
            <div class="columns">{{user.wikiName}}</div>
        </div>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">{{maketext('UID')}}:</div>
            <div class="columns">{{user.id}}</div>
        </div>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">{{maketext('Email')}}</div>
            <div class="columns">{{user.email}}</div>
        </div>
        <span class="section-title">{{maketext('Group memberships')}}</span>
        <p v-html="maketext(strings.addUserToGroup, ['<b>'+user.displayName+'</b>'])"></p>
        <group-selector ref="groupSelector"></group-selector>
        <button class="primary button small pull-right" @click="addUserToGroup">{{maketext('Add to group')}}</button>

        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{maketext('Name')}}</th><th>{{maketext('Source')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="group in user.groups">
                <td :title="group.name">{{group.name}}</td>
                <td :title="group.provider">{{group.provider}}</td>
                <td :title="maketext('Remove user from group')"><i @click="removeUserFromGroup(group)" class="fa fa-trash fa-2x click" aria-hidden="true"></i></td>
            </tr>
        </tbody>
        </table>
    </div>
</template>

<script>
import MaketextMixin from './MaketextMixin.vue'
import GroupSelector from './GroupSelector';

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
    data() {
        return {
            strings: {
                addUserToGroup: "Add [_1] to an existing group.",
            },
        }
    },
    components: {
        GroupSelector
    },
    computed: {
        user(){
            if(this.propsData){
                return this.propsData.user;
            }
        }
    },
    methods: {
        addUserToGroup() {
            let selectedValues = this.$refs.groupSelector.getSelectedValues();
            let self = this
            let params = {
                cuids: this.user.id,
                group: selectedValues[0],
                wikiName: this.user.wikiName
            }
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/addUsersToGroup", params)
            .done((result) => {
                makeToast.call(self, 'success', this.maketext("Add User to Group successfull"));
                self.user.groups.push({name: selectedValues[0].name, provider: ''});
                self.$refs.groupSelector.clearSelectedValues();
            })
            .fail((xhr) => {
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
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/removeUserFromGroup", params)
            .done((result) => {
                makeToast.call(self, 'success', this.maketext("Removed User from Group successfull"));
                let index = self.user.groups.indexOf(group);
                self.user.groups.splice(index, 1);
            })
            .fail((xhr) => {
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
