<template>
    <div>
        <div class="section-title">
            <span>{{maketext('Register new group')}}</span>
            <p class="sub">{{maketext('Think twice before restricting write access to a web or a topic, because an open system where everybody can contribute is the essence of a wiki culture.')}}</p>
        </div>
    <form>
        <input v-model="groupData.name" type="text" name="groupName" :placeholder="maketext('Group name')" aria-describedby="groupNameHelpText">
        <br/>
        <p class="help-text" id="groupNameHelpText"><strong>{{maketext("Notice:")}}</strong> <span v-html="maketext('A group name must be a [_1] and <b>must</b> end in ...Group.', [wikiNameLink])"></span></p>
        <br/>
        <div class="section-title">
            <span>{{maketext('Group members')}}</span>
        </div>
        <ua-entity-selector user group multiple ref="userSelector"></ua-entity-selector>
        <button type="button" v-on:click="registerGroup" class="primary button small pull-right">{{maketext('Register group')}}</button>
    </form>
    </div>
</template>

<script>
/*global $ sidebar foswiki */
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
    data() {
        return {
            groupData: {
                name: "",
            },
            wikiNameLink: "<a href='" + foswiki.getScriptUrl('view') + "/" + foswiki.getPreference("SYSTEMWEB")+ "/WikiName" + "' target='_blank'>" + this.maketext("unique WikiName") + "</a>",
        }
    },
    computed: {
    },
    components: {
        UaEntitySelector
    },
    methods: {
        registerGroup() {
            var self = this;
            var selectedValues = this.$refs.userSelector.getSelectedValues();
            var params = {
                group: {name: this.groupData.name},
                cuids: selectedValues,
                create: 1
            }

            if (!this.groupData.name) {
                makeToast.call(self, 'alert', 'Field GroupName is required');
                return;
            }
            if (!(foswiki.RE.wikiword.test(this.groupData.name) && /Group$/.test(this.groupData.name))) {
                makeToast.call(self, 'alert', 'GroupName must be a wiki word and ends with Group');
                return;
            }
            sidebar.makeModal({type: 'spinner', autoclose: false});
            $.post(foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'addUsersToGroup'), {params: JSON.stringify(params)})
            .done(() => {
                makeToast.call(self, 'success', 'Registration successfull');
                //TODO: open view of Group
                self.groupData.name = '';
                self.$refs.userSelector.clearSelectedValues();
            }).fail((xhr) => {
                var response = JSON.parse(xhr.responseText);
                makeToast.call(self, 'alert', response.msg);
            }).always(() => sidebar.hideModal());
        }
    },
    created: function() {
        var self = this;
        sidebar.$vm.header = {
            right: [
                {
                    type: 'button',
                    color: 'primary',
                    text: self.maketext('Register group'),
                    callback: function() {self.registerGroup();}
                }
            ]
        };
    }
}
</script>
<style lang="sass">
label.checkbox-label{
    padding: 0px 0px 11px 0px;
}
</style>
