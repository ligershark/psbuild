namespace PSBuild.Extensions {
    using MarkdownLog;
    using System;
    using System.Linq;
    using System.Collections.Generic;

    public static class MdExtensions {
        public static RawMarkdown ToMarkdownRawMarkdown(this string text){
            return new RawMarkdown(text);
        }

        public static string ToMarkdown(this List<IMarkdownElement> list) {
            return string.Join(Environment.NewLine, list.Select(i => i.ToMarkdown()));
        }
    }
}
