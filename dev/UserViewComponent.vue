<template>
    <div>
        <h1 class="primary">{{user.displayName}}</h1>
        <div class="row align-middle details">
            <div class="columns title">{{maketext('WikiName')}}:</div>
            <div class="columns small-7">{{user.wikiName}}</div>
        </div>
        <div class="row align-middle details">
            <div class="columns title">{{maketext('UID')}}:</div>
            <div class="columns small-7">{{user.id}}</div>
        </div>
        <div class="row align-middle details">
            <div class="columns title">{{maketext('Email')}}:</div>
            <div class="columns small-7">{{user.email}}</div>
        </div>
        <h1>Membership in Groups</h1>
        <span v-html="maketext(strings.addUserToGroup, ['<b>'+user.displayName+'</b>'])"></span>
        <group-selector ref="groupSelector"></group-selector>
        <button class="primary button small pull-right" @click="addUserToGroup">{{maketext('Add to Group')}}</button>

        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{maketext('Name')}}</th><th>{{maketext('Source system')}}</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="group in user.groups"><td>{{group.name}}</td><td>{{group.provider}}</td><td><i class="fa fa-trash fa-2x" aria-hidden="true"></i></td></tr>
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
