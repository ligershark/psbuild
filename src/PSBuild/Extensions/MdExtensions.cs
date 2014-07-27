namespace PSBuild.Extensions {
    using MarkdownLog;

    public static class MdExtensions {
        public static RawMarkdown ToMarkdownRawMarkdown(this string text){
            return new RawMarkdown(text);
        }
    }
}
