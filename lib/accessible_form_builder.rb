# require "form_builder_helper"

module GoodForm

  GROUP_WRAPPER_ELEMENT = 'fieldset' # ul, ol
  FIELD_WRAPPER_ELEMENT = 'label' # li
  AF_FORM_CLASS = 'af_form'
  AFTER_LABEL_CONTENT = ":"

  class GoodFormBuilder < ActionView::Helpers::FormBuilder

    ActionView::Helpers::AssetTagHelper.register_javascript_include_default("inline_mozilla_hack.js")

    # need to keep track of these so we can read then nuke/read
    # them before calling out to super for original form helpers
    #AF_GRID_OPTIONS = [:span, :append, :prepend, :push, :pull]
    AF_TOGGLE_OPTIONS = [:continue, :last]

    # what to override / wrap and how
    ADDITIONAL_HELPER_METHODS = %w(date_select datetime_select time_select collection_select time_zone_select)
    FORM_BUILDER_METHODS = ActionView::Helpers::FormHelper.instance_methods
    MANUAL_NEW_METHODS = %w(label hidden_field select radio_button check_box)
    EXCLUDED_METHODS = %w(form_for fields_for) # see af_form_for, af_fields_for
    AFTER_METHODS = %w(radio_button check_box)
    NO_LABEL_METHODS = %w(submit)
    
    AUTO_WRAP = ADDITIONAL_HELPER_METHODS + FORM_BUILDER_METHODS - EXCLUDED_METHODS
    BARE_WRAP = AUTO_WRAP + MANUAL_NEW_METHODS

    # generate access to original helpers, prefixed with bare, ie bare_text_field
    BARE_WRAP.each do |selector|
      bare_method = ('bare_' + selector.to_s).to_sym
      alias_method bare_method, selector unless method_defined?(bare_method)
    end

    # define methods which have a 'field, options' signature
    # other methods will need to be custom wrapped below
    AUTO_WRAP.each do |selector|
      src = <<-END_SRC
      def #{selector}(field, options = {})
        label_text, af_options = extract_af_options(field, reflect_field_type, options)
        generic_field( field, super, label_text, options.merge(af_options))
      end
      END_SRC
      class_eval src, __FILE__, __LINE__
    end

    def submit(text, options = {})
      # don't need label_text, just af_options for submit buttons
      label_text, af_options = extract_af_options(nil, reflect_field_type, options)
      generic_field(nil, @template.submit_tag(text, options), nil, options.merge(af_options))
    end

    def hidden_field(*args)
      super
    end

    # TODO fix up string mashing - use fieldset helper etc
    # creates fieldsets the ghetto way. should be block/yield combo :(
    def separator(new_section_name, options = {})
      separator_class = options[:class] ? %Q[ class="#{options[:class]}"] : ''
      separator_id = options[:id] ? %Q[ id="#{options[:id]}"] : ''
      <<-HTML
    </fieldset>
    <fieldset#{separator_id}#{separator_class}><legend>#{new_section_name}</legend>
    HTML
  end

  def radio_button(field, tag_value, options = {})
    label_text, af_options = extract_af_options(field, reflect_field_type, options)
    generic_field( field, super, tag_value, options.merge(af_options).merge(:field_order => [:field, :label, :required, :note]) )
  end

  def check_box(field, options={}, checked_value="1", unchecked_value="0")
    label_text, af_options = extract_af_options(field, reflect_field_type, options)
    generic_field( field, super, label_text, options.merge(af_options).merge(:field_order => [:field, :label, :required, :note]) )
  end

  def select(field, choices, options = {}, html_options = {})
    label_text, af_options = extract_af_options(field, reflect_field_type, options)
    generic_field( field, super, label_text, options.merge(af_options))
  end

  def collection_select(field, collection, value_method, text_method, options = {}, html_options = {})
    label_text, af_options = extract_af_options(field, reflect_field_type, options)
    generic_field( field, super, label_text, options.merge(af_options))
  end

  def time_zone_select(field, priority_zones = nil, options = {}, html_options = {})
    label_text, af_options = extract_af_options(field, reflect_field_type, options)
    generic_field( field, super, label_text, options.merge(af_options))
  end

  protected
  def generic_field(fieldname, field, label_text = nil, options = {})
    label_order, field_order, field_type, structure, required, note = extract_field_options(options)

    label_components = {
      :required => required,
      :label_text => label_text
    }

    label_text.blank? && (field_order.delete(:label))
    label_contents = label_order.map{ |c| label_components[c] }.join('')
    label_for = "#{@object_name}_#{fieldname}"
    
    set_css_class = [field_type, structure].compact.join(' ').rstrip
    
    field_components = {
      :label => AFTER_METHODS.include?(field_type) ? label(label_contents, label_for, :class => set_css_class ) : label_contents + "<br />",
      :field => field,
      :note => note,
      :required => required
    }

    content = field_order.map{ |c| field_components[c] }.compact.join('')
    
    unless AFTER_METHODS.include?(field_type) || NO_LABEL_METHODS.include?(field_type)
      @template.content_tag 'label', content, {:for => label_for, :class => set_css_class}
    else
      content
    end
    
    #@template.content_tag(FIELD_WRAPPER_ELEMENT, content, (structure.blank? ? nil : {:class => set_css_class}))
  end

  # replace this with label_tag helper when dropping support for pre 2.x series
  def label(text, for_field, options = {})
    @template.content_tag 'label', text, {:for => for_field}.merge(options)
  end

  # these options must be deleted, so when the wrapped form helpers call super,
  # they are not sucked along - they'd make for invalid html/xhtlm attributes
  def extract_af_options(field, field_type, options)
    label_text = options.delete(:label) || field.to_s.humanize
    required = options.delete(:required) || false
    note = options.delete(:note) || false
    structure = extract_layout_options(options)
    return [label_text, AFTER_LABEL_CONTENT].join, {:required => required, :structure => structure, :note => note, :field_type => field_type}
  end

  # need the name of the field type for the helper we're creating
  # in order to add it as a class name to the corresponding label.
  def reflect_field_type
    caller[0] =~ /`([^']*)'/ and $1
  end

  # build up presentational / structural class names
  def extract_layout_options(options)
    structure = ['set'] # set is the structural building block class

    AF_TOGGLE_OPTIONS.each do |attr|
      # ':continue => true' becomes 'continue'
      structure << (options.delete(attr) ? attr.to_s : '')
    end

    structure.compact.join(' ')
  end

  def extract_field_options(options)
    label_order = options.delete(:label_order) || [:required, :label_text]
    field_order = options.delete(:field_order) || [:label, :field, :note]
    field_type = options.delete(:field_type) || ''
    structure = options.delete(:structure) || ''
    required = options[:required] ? @template.content_tag('span', '&nbsp*&nbsp;', :class => 'required_field') : ''
    note = options[:note] ? @template.content_tag('em', " #{options[:note]} ", :class => 'note') : ''
    return label_order, field_order, field_type, structure, required, note
  end

end

def af_form_for(object_name, *args, &proc)
  options = args.last.is_a?(Hash) ? args.last : {}
  af_set_form_classes(options)
  prefix, postfix = af_prefix_postfix(object_name, options)

  custom_form_for( GoodFormBuilder, prefix, postfix,
  form_tag(options.delete(:url) || {}, options.delete(:html) || {}),
  object_name, *args, &proc)
end

def af_remote_form_for(object_name, *args, &proc)
  options = args.last.is_a?(Hash) ? args.last : {}
  af_set_form_classes(options)
  prefix, postfix = af_prefix_postfix(object_name, options)

  custom_form_for( AfFormBuilder, prefix, postfix,
  form_remote_tag(options),
  object_name, *args, &proc)
end

def af_fields_for(object_name, *args, &proc)
  options = args.last.is_a?(Hash) ? args.last : {}
  af_set_form_classes(options)
  prefix, postfix = af_prefix_postfix(object_name, options)

  custom_fields_for( AfFormBuilder, prefix, postfix, object_name, *args, &proc)
end

def custom_form_for(builder, fields_pre, fields_post, form_tag, object_name, *args, &proc)
  concat(form_tag)
  custom_fields_for(builder, fields_pre, fields_post, object_name, *args, &proc)
  concat("</form>")
end

def custom_fields_for(builder, fields_pre, fields_post, object_name, *args, &proc)
  raise ArgumentError, "Missing block for form_for/fields_for call." unless block_given?
  options = args.last.is_a?(Hash) ? args.pop : {}
  concat(fields_pre)
  fields_for(object_name, *(args << options.merge(:builder => builder)), &proc)
  concat(fields_post)
end

protected

# TODO: css ID's should be unique, but if some partial is rendering
# a form or fieldset a bunch of times, it currently won't be unique.
# Use the partial counter: http://www.pgrs.net/2007/7/20/render-partial-with-collection-has-hidden-counter
# appended to the css id generated herein?
def af_prefix_postfix(object_name, options)
  prefix = options.delete(:prefix)
  postfix = options.delete(:postfix)
  group_id = object_name.to_s.gsub(/(\W|_)+/, '_') + 'fields'

  # legends are only valid for fieldsets
  legend = GROUP_WRAPPER_ELEMENT == 'fieldset' ? options.delete(:legend) : ''
  legend = legend.blank? ? '' : "<legend>#{legend}</legend>"

  prefix = prefix.blank? ? %Q(<#{GROUP_WRAPPER_ELEMENT} id="#{group_id}">) + legend.to_s : prefix
  postfix = postfix.blank? ? "</#{GROUP_WRAPPER_ELEMENT}>" : postfix

  return prefix, postfix
end

def af_set_form_classes(options)
  default_class = [AF_FORM_CLASS].join(' ')
  options[:html] ||= { :class => default_class }
  option_class = options[:html][:class].to_s
  options[:html][:class] = option_class.blank? \
  ? default_class \
  : [option_class, default_class].join(" ")
end

end