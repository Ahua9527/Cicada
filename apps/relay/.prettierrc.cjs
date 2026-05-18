module.exports = {
  // 基础格式化
  semi: true,
  trailingComma: 'es5',
  singleQuote: true,
  printWidth: 100,
  tabWidth: 2,
  useTabs: false,
  
  // 箭头函数
  arrowParens: 'avoid',
  
  // 换行符
  endOfLine: 'lf',
  
  // 对象和数组
  bracketSpacing: true,
  bracketSameLine: false,
  
  // TypeScript
  parser: 'typescript',
  
  // 覆盖特定文件类型的配置
  overrides: [
    {
      files: '*.json',
      options: {
        parser: 'json',
        printWidth: 80
      }
    },
    {
      files: '*.md',
      options: {
        parser: 'markdown',
        printWidth: 80,
        proseWrap: 'always'
      }
    },
    {
      files: '*.yaml',
      options: {
        parser: 'yaml',
        tabWidth: 2
      }
    }
  ]
};
