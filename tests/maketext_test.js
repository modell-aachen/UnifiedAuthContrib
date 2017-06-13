import MaketextMixin from '../dev/MaketextMixin.vue'
import './mockup_functions/foswiki.js'

describe("the Maketext Mixin", () => {
    it('should pass the correct parameters to jsi18n', () => {
        let translation = MaketextMixin.methods.maketext("Hello [_1] [_2]", ["A","B"]);
        expect(translation).toBe("MT:UnifiedAuth,Hello [_1] [_2],A,B")
    });
});
