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
            <tr><th>{{maketext('Name')}}</th><th>{maketext('Source')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="group in user.groups">
                <td :title="group.name">{{group.name}}</td>
                <td :title="group.provider">{{group.provider}}</td>
                <td title="{{gettext('Remove user from group')}}"><i class="fa fa-trash fa-2x" aria-hidden="true"></i></td>
            </tr>
        </tbody>
        </table>
    </div>
</template>

<script>
import MaketextMixin from './MaketextMixin.vue'
import GroupSelector from './GroupSelector';

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
            let params = {
                cuids: this.user.id,
                group: selectedValues[0],
                wikiName: this.user.wikiName
            }
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/addUsersToGroup", params)
            .done((result) => {
                sidebar.makeToast({
                    closetime: 2000,
                    color: "success",
                    text: "Add User to Group successfull"
                });
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

.columns.title {
    color: #97938b;
}
</style>
