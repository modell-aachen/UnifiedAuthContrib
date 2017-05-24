<template>
    <div>
        <span class="section-title">{{user.displayName}}</span>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">WikiName:</div>
            <div class="columns">{{user.wikiName}}</div>
        </div>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">cUID:</div>
            <div class="columns">{{user.id}}</div>
        </div>
        <div class="row align-middle collapse">
            <div class="columns small-4 title">{{gettext('Email')}}</div>
            <div class="columns">{{user.email}}</div>
        </div>
        <span class="section-title">{{gettext('Group memberships')}}</span>
        <p>{{gettext("Add [_1] to an existing group", user.displayName)}}</p>
        <group-selector></group-selector>
        <button class="primary button small pull-right">{{gettext('Add to group')}}</button>

        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>{{gettext('Name')}}</th><th>{{gettext('Source')}}</th><th></th></tr>
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
import GroupSelector from './GroupSelector';
export default {
    props: ['propsData'],
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
        gettext(text, param) {
            return foswiki.jsi18n.get('UnifiedAuth', text, param);
        },
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
