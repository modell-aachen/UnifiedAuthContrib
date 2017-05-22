<template>
    <div>
        <h1>{{user.displayName}}</h1>
        <div class="row align-middle details">
            <div class="columns title">WikiName:</div>
            <div class="columns small-7">{{user.wikiName}}</div>
        </div>
        <div class="row align-middle details">
            <div class="columns title">UID:</div>
            <div class="columns small-7">{{user.id}}</div>
        </div>
        <div class="row align-middle details">
            <div class="columns title">Email:</div>
            <div class="columns small-7">{{user.email}}</div>
        </div>
        <h1>Gruppen</h1>
        <group-selector></group-selector>
        <button class="primary button small pull-right">Zu Gruppe hinzufügen</button>

        <table class="ma-table ma-data-table">
        <thead>
            <tr><th>Name</th><th>Quellsystem</th><th></th></tr>
        </thead>
        <tbody>
            <tr v-for="group in user.groups"><td>{{group.name}}</td><td>{{group.provider}}</td><td><i class="fa fa-trash fa-2x" aria-hidden="true"></i></td></tr>
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
    }
}
</script>