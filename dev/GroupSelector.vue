<template>
<div>
<vue-select v-model="selectedValues" :options="options" :on-search="onSearch":get-option-label="getOptionLabel" :on-open="onOpen" :prevent-search-filter="true"></vue-select>
</div>
</template>

<script>
import VueSelect from 'vue-select/src/index.js';
export default {
    data() {
        return {
            options: [],
            selectedValues: []
        }
    },
    components: {
        VueSelect
    },
    computed: {
    },
    methods: {
        fetchOptions(search) {
            $.getJSON(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/groups/")
            .done((result) => {
                this.options = result;
            });
        },
        onSearch() {

        },
        onOpen() {
            this.options = [];
            this.fetchOptions();
        },
        getOptionLabel(option){
            return option.name;
        },
        getSelectedValues() {
            return this.selectedValues;
        }
    }
}
</script>
