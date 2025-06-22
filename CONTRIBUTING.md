# Contributing to Conky Themes & Widgets

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## 🤝 How to Contribute

### Types of Contributions

- 🎨 **New Themes** - Complete Conky themes
- 🔧 **Widgets** - Individual components or widgets
- 🐛 **Bug Fixes** - Fixes for existing themes
- 📚 **Documentation** - Improvements to docs
- 🎯 **Performance** - Optimizations and improvements

### Getting Started

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create** a new branch for your contribution
4. **Make** your changes
5. **Test** thoroughly
6. **Submit** a pull request

## 📋 New Theme Guidelines

### Theme Structure
Each theme should follow this structure:
```
theme-name/
├── README.md           # Theme documentation
├── install.sh          # Installation script
├── .gitignore         # Theme-specific gitignore
├── LICENSE            # License file (if different)
├── main-config-file   # Primary Conky configuration
├── additional-files   # Any additional scripts/configs
└── assets/
    ├── screenshot.png # Theme preview
    └── resources/     # Any required resources
```

### Required Files

#### README.md
- Clear description of the theme
- Screenshot/preview image
- Installation instructions
- Dependencies list
- Configuration options
- Troubleshooting section

#### install.sh
- Dependency checking
- Directory setup
- Configuration file creation
- Clear success/error messages

### Theme Requirements

#### Technical Standards
- **Portable** - Use relative paths only
- **Self-contained** - All resources in theme directory
- **Documented** - Clear inline comments
- **Tested** - Works on major Linux distributions

#### Visual Standards
- **Screenshot** - High-quality preview image
- **Clean Design** - Modern, readable interface
- **Customizable** - Easy color/position changes
- **Responsive** - Works on different screen sizes

### Code Quality

#### Conky Configuration
```bash
# Good: Relative paths
lua_load './script.lua'
${image ./assets/image.png}

# Bad: Absolute paths
lua_load '/home/user/.conky/script.lua'
${image /home/user/.conky/assets/image.png}
```

#### Shell Scripts
- Use `#!/bin/bash` shebang
- Include error handling with `set -e`
- Provide informative output messages
- Check dependencies before proceeding

#### Lua Scripts (if applicable)
- Clear variable naming
- Proper error handling
- Efficient API usage
- Commented functions

## 🐛 Bug Reports

### Before Reporting
- Check existing issues
- Test on clean installation
- Gather system information

### Include in Report
- **OS**: Distribution and version
- **Conky Version**: Output of `conky --version`
- **Theme**: Which theme is affected
- **Steps to Reproduce**: Detailed steps
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Screenshots**: If visual issue
- **Logs**: Any error messages

## 🔧 Pull Request Process

### Before Submitting
1. **Test** your changes thoroughly
2. **Update** documentation if needed
3. **Follow** the coding standards
4. **Check** that install scripts work
5. **Verify** screenshots are up to date

### Pull Request Template
```
## Description
Brief description of changes

## Type of Change
- [ ] New theme
- [ ] Bug fix
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Other (specify)

## Testing
- [ ] Tested on Ubuntu/Debian
- [ ] Tested on Arch Linux
- [ ] Tested on Fedora
- [ ] Installation script works
- [ ] All features functional

## Screenshots
If applicable, add screenshots

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No hardcoded paths
- [ ] Install script included
```

## 📝 Style Guidelines

### File Naming
- Use lowercase with hyphens: `theme-name`
- Descriptive names: `music-player` not `mp`
- Consistent extensions: `.lua`, `.sh`, `.md`

### Documentation
- Use markdown formatting
- Include code examples
- Provide clear installation steps
- Add troubleshooting section

### Comments
```bash
# Configuration section
alignment top_right     # Position on screen
gap_x 10               # Horizontal offset
gap_y 10               # Vertical offset
```

## 🧪 Testing

### Local Testing
```bash
# Test installation script
cd theme-name
./install.sh

# Test theme functionality
conky -c config-file

# Test on different systems
# - Different Linux distributions
# - Different screen resolutions
# - Different Conky versions
```

### Integration Testing
- Verify theme works with other themes
- Check resource usage
- Test startup/shutdown behavior

## 📚 Documentation Standards

### README Structure
1. **Title & Description**
2. **Screenshot**
3. **Features List**
4. **Requirements**
5. **Installation**
6. **Configuration**
7. **Troubleshooting**
8. **Contributing**
9. **License**

### Code Documentation
- Comment complex logic
- Explain configuration options
- Document API usage
- Include usage examples

## 🏷️ Release Process

### Version Numbering
- Major: Breaking changes
- Minor: New features
- Patch: Bug fixes

### Release Checklist
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Screenshots current
- [ ] CHANGELOG updated
- [ ] Version numbers bumped

## 💬 Community

### Getting Help
- **Issues**: For bug reports and feature requests
- **Discussions**: For questions and general chat
- **Discord**: Real-time community chat (if available)

### Code of Conduct
- Be respectful and inclusive
- Help others learn and contribute
- Focus on constructive feedback
- Follow the golden rule

## 📞 Contact

- **Maintainer**: [Your Name]
- **Email**: your-email@example.com
- **GitHub**: [@your-username]

---

Thank you for contributing to the Conky community! 🎉
