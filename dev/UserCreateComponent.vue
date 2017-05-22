<template>
    <div>
        <h1>Register new user</h1>
        <p>Here you can register a new wiki user. The user will get a confirmation e-mail with the login data after the registration.</p>
    <form>
        <input v-model="userData.firstName" type="text" name="firstName" placeholder="First name">
        <input v-model="userData.lastName" type="text" name="lastName" placeholder="Last name">
        <input v-model="userData.email" type="text" name="email" placeholder="Email address" aria-describedby="emailHelpText">
        <p class="help-text" id="emailHelpText"><strong>Notice:</strong> Your Email address will not be published.</p>
        <br>
        <input v-model="wikiName" type="text" name="wikiName" placeholder="WikiName" aria-describedby="wikiNameHelpText">
        <p class="help-text" id="wikiNameHelpText"><strong>Notice:</strong> Your name that is visible in Q.wiki. This has to be a unique name.</p>
        <input v-model="generatePassword" id="generatePasswordCheckbox" type ="checkbox">
        <label for="generatePasswordCheckbox">
             Generate password
        </label>
        <div v-show="!generatePassword">
            <input v-model="userData.password" type="password" name="password" placeholder="Password">
            <input v-model="userData.passwordConfirmation" type="password" name="passwordConfirmation" placeholder="Confirm password">
        </div>
        <button type="button" v-on:click="registerUser" class="primary button small pull-right">Register user</button>
    </form>
    </div>
</template>

<script>
export default {
    data() {
        return {
            generatePassword: false,
            userData: {
                firstName: "",
                lastName: "",
                email: "",
                password: "",
                passwordConfirmation: ""
            }
        }
    },
    computed: {
        wikiName(){
            return $.wikiword.wikify(this.userData.firstName + this.userData.lastName, {transliterate: true});
        },
        isPasswordCorrect(){
            if(this.userData.password !== this.userData.passwordConfirmation){
                return false;
            }

            if(!this.userData.password){
                return false;
            }

            return true;
        }
    },
    methods: {
        registerUser() {
            let params = {
                loginName: this.wikiName,
                wikiName: this.wikiName,
                email: this.userData.email
            }
            if(!this.generatePassword){
                params.password = this.userData.password;
            }
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/registerUser", params)
            .done((result) => {
                sidebar.makeToast({
                    closetime: 2000,
                    color: "success",
                    text: "Registration successfull"
                });
            })
        }
    }
}
</script>