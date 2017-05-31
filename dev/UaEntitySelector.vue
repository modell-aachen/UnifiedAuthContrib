<template>
<div class="vue-select-wrapper">
<vue-select :multiple="multiple" v-model="selectedValues" label="name" :options="options" :on-search="fetchOptions" :get-option-label="getOptionLabel" :get-selected-option-label="getSelectedValuesLabel" :on-open="fetchOptions" :prevent-search-filter="true"></vue-select>
</div>
</template>

<script>
/* global $ foswiki */
import VueSelect from 'vue-select/src/index.js';
export default {
    props: {
        multiple: {
            type: Boolean
        },
        user: {
            type: Boolean
        },
        group: {
            type: Boolean
        }
    },
    data() {
        return {
            options: [],
            selectedValues: []
        }
    },
    components: {
        VueSelect
    },

    methods: {
        fetchOptions(search, loading) {
            let params = {
                q: search,
                group: this.group ? 1 : 0,
                user: this.user ? 1 : 0
            }
            if( typeof loading === "function"){
                loading(true);
            }
            $.getJSON(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/users/", params)
            .done((result) => {
                this.options = result;
            })
            .always(() => {
                if( typeof loading === "function"){
                    loading(false);
                }
            });
        },
        onSearch(search, loading) {
            this.fetchOptions(search, loading);
        },
        getOptionLabel(option){
            return option.name;
        },
        getSelectedValues() {
            return this.selectedValues;
        },
        getSelectedValuesLabel(option) {
            return option.name;
        },
        clearSelectedValues(){
            this.selectedValues = null;
        }
    }
}
</script>
