require(File.expand_path('report/cell', File.dirname(__FILE__)))
require(File.expand_path('report/row', File.dirname(__FILE__)))
# require_relative './report/cell'
# require_relative './report/row'

module XeroGateway
  class Report

    include Money
    include Dates

    attr_reader   :errors
    attr_accessor :report_id, :report_name, :report_type, :report_titles, :report_date, :updated_at,
                  :body, :column_names

    alias :rows :body

    def initialize(params={})
      @errors         ||= []
      @report_titles  ||= []
      @body           ||= []

      params.each do |k,v|
        self.send("#{k}=", v)
      end
    end

    class << self

      def from_xml(report_element)
        report = Report.new
        report_element.children.each do | element |
          case element.name
            when 'ReportID'         then report.report_id = element.text
            when 'ReportName'       then report.report_name = element.text
            when 'ReportType'       then report.report_type = element.text
            when 'ReportTitles'
              each_title(element) do |title|
                report.report_titles << title
              end
            when 'ReportDate'       then report.report_date = Date.parse(element.text)
            when 'UpdatedDateUTC'   then report.updated_at = parse_date_time_utc(element.text)
            when 'Rows'
              report.column_names ||= find_body_column_names(element)
              each_row_content(element) do |row|
                report.body << row
              end
          end
        end
        report
      end

      private

        def each_row_content(xml_element, &block)
          column_names    = find_body_column_names(xml_element).values
          report_sections = REXML::XPath.each(xml_element, "//RowType[text()='Section']/parent::Row")

          report_sections.each do |section_row|
            section_name = section_row.get_elements("Title").first.try(:text)
            section_row.elements.each("Rows/Row") do |xpath_cells|
              values = find_body_cell_values(xpath_cells)
              yield Row.new(column_names, values, section_name)
            end
          end
        end

        def each_title(xml_element, &block)
          xpath_titles = REXML::XPath.first(xml_element, "//ReportTitles")
          xpath_titles.elements.each("//ReportTitle") do |xpath_title|
            title = xpath_title.text.strip
            yield title if block_given?
          end
        end

        def find_body_cell_values(xml_cells)
          values = []
          xml_cells.elements.each("Cells/Cell") do |xml_cell|
            if value = xml_cell.children.first # finds <Value>...</Value>
              values << Cell.new(value.text.try(:strip), collect_attributes(xml_cell))
              next
            end
            values << nil
          end
          values
        end

        # Collects "<Attribute>" elements into a hash
        def collect_attributes(xml_cell)
          Array.wrap(xml_cell.elements["Attributes/Attribute"]).inject({}) do |hash, xml_attribute|
            if (key   = xml_attribute.elements["Id"].try(:text)) &&
              (value = xml_attribute.elements["Value"].try(:text))

              hash[key] = value
            end
            hash
          end.symbolize_keys
        end

        # returns something like { column_1: "Amount", column_2: "Description", ... }
        def find_body_column_names(body)
          header       = REXML::XPath.first(body, "//RowType[text()='Header']")
          names_map    = {}
          column_count = 0
          header.parent.elements.each("Cells/Cell") do |header_cell|
            column_count += 1
            column_key    = "column_#{column_count}".to_sym
            column_name   = nil
            name_value    = header_cell.children.first
            column_name   = name_value.text.strip unless name_value.blank? # finds <Value>...</Value>
            names_map[column_key] = column_name
          end
          names_map
        end
    end

  end
end
