<template>
    <div>
        <span class="section-title">{{group.displayName}}</span>
        <template v-if="canModifyGroup">
            <span v-html="maketext('Add user or group to the <b>[_1]</b>', group.displayName)"></span>
            <ua-entity-selector user group multiple ref="userSelector"></ua-entity-selector>
            <button class="primary button small pull-right" @click="addUserToGroup">{{maketext('Add user/ group')}}</button>
        </template>

        <br/>
        <span class="section-title">{{maketext("All contained groups")}}</span>
        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{maketext('Name')}}</th><th>{{maketext('Source')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="group in nestedGroups">
                <td :title="group.name">{{group.name}}</td>
                <td :title="group.provider">{{group.provider}}</td>
                <td :title="maketext('Remove group from group')"><i @click="removeUserFromGroup(group)" class="fa fa-trash fa-2x click" aria-hidden="true"></i></td>
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
                <td :title="member.display_name">{{member.display_name}}</td>
                <td :title="member.group_names">{{member.group_names}}</td>
                <td :title="maketext('Remove user from group')"><i v-if="member.group_names.match(group.displayName)" @click="removeUserFromGroup(member)" class="fa fa-trash fa-2x click" aria-hidden="true"></i></td>
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
        },
        canModifyGroup(){
            return !/(NobodyGroup|BaseGroup)/.test(this.group.displayName) && /Group$/.test(this.group.displayName)
        },
        nestedGroups(){
             var result = [];
             var lookup = {[this.group.displayName]: 1};
             for(var i = 0; i < this.group.members.length; i++){
                var group_name = this.group.members[i].group_names;
                var group_names = group_name.split(", ");
                var p_name = this.group.members[i].g_provider_name;
                var p_names = p_name.split(", ");
                for(var j = 0; j < p_names.length; j++){
                    if(!(group_names[j] in lookup)) {
                        lookup[group_names[j]] = 1;
                        result.push({name: group_names[j], provider: p_names[j]});
                    }
                }
             }
             return result;
        }
    },
    methods: {
        addUserToGroup() {
            var self = this;
            var selectedValues = this.$refs.userSelector.getSelectedValues();
            var params = {
                group: {name: this.group.displayName},
                cuids: selectedValues,
                create: 0
            }

            sidebar.makeModal({type: 'spinner', autoclose: false});
            $.post(foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'addUsersToGroup'), params)
            .done(() => {
                makeToast.call(self, 'success', this.maketext("Add User to Group successfull"));
                self.$refs.userSelector.clearSelectedValues();
                //TODO: open view of Group
            }).fail((xhr) => {
                var response = JSON.parse(xhr.responseText);
                makeToast.call(self, 'alert', response.msg);
            }).always(() => sidebar.hideModal());
        },
        removeUserFromGroup(member) {
            var self = this
            var params = {
                cuids: member.cuid,
                group: this.group.displayName,
                wikiName: member.wiki_name
            }
            sidebar.makeModal({
                type: 'spinner'
            });
            $.post(foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'removeUserFromGroup'), params)
            .done(() => {
                sidebar.hideModal();
                makeToast.call(self, 'success', this.maketext("Removed User from Group successfull"));
                var index = self.group.members.indexOf(member);
                self.group.members.splice(index, 1);
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
