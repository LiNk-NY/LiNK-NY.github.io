---
# Leave the homepage title empty to use the site title
title: ''
date: 2022-10-24
type: landing

sections:
  - block: about.biography
    id: about
    content:
      title: Biography
      # Choose a user profile to display (a folder name within `content/authors/`)
      username: admin
    design:
      background:
        image:
          filename: dark_stripes.png
          size: actual
          parallax: false
          position: left
  - block: skills
    content:
      title: Skills
      text: ''
      # Choose a user to display skills from (a folder name within `content/authors/`)
      username: admin
    design:
      columns: '1'
  - block: experience
    content:
      title: Experience
      # Date format for experience
      #   Refer to https://docs.hugoblox.com/customization/#date-format
      date_format: Jan 2006
      # Experiences.
      #   Add/remove as many `experience` items below as you like.
      #   Required fields are `title`, `company`, and `date_start`.
      #   Leave `date_end` empty if it's your current employer.
      #   Begin multi-line descriptions with YAML's `|2-` multi-line prefix.
      items:
        - title: Senior Data Scientist
          company: Research Foundation CUNY
          company_url: 'https://www.rfcuny.org/RFWebsite'
          location: 'New York, NY'
          date_start: '2014-01-01'
          date_end: ''
          description: ''

        - title: Lead Biostatistician
          company: Roswell Park Comprehensive Cancer Center
          company_url: 'https://roswellpark.org'
          location: 'Buffalo, NY'
          date_start: '2016-01-01'
          date_end: ''
          description: ''
        
        - title: Adjunct Lecturer
          company: CUNY School of Public Health
          company_url: 'https://sph.cuny.edu'
          location: 'New York, NY'
          date_start: '2016-01-01'
          date_end: '2023-07-01'
    design:
      columns: '2'
  - block: accomplishments
    content:
      # Note: `&shy;` is used to add a 'soft' hyphen in a long heading.
      title: 'Certificates'
      subtitle:
      # Date format: https://docs.hugoblox.com/customization/#date-format
      date_format: Jan 2006
      # Accomplishments.
      #   Add/remove as many `item` blocks below as you like.
      #   `title`, `organization`, and `date_start` are the required parameters.
      #   Leave other parameters empty if not required.
      #   Begin multi-line descriptions with YAML's `|2-` multi-line prefix.
      items:
        - certificate_url: https://drive.google.com/file/d/1NDBHoKxLEBVL1lQiPGcP40F8WyqUN-5o/view
          date_start: '2019-04-14'
          date_end: '2019-05-11'
          description: ''
          organization: Central Michigan University
          organization_url: https://www.cmich.edu
          title: Workshop in Online Instruction
          url: ''
        - certificate_url: https://drive.google.com/file/d/0B-4RWfCJ8jHyN3VEd1Nma0NyVHM/view
          date_end: '2017-07-08'
          date_start: '2017-07-01'
          organization: El Nodo Nacional de Bioinformatica y la Sociedad Iberoamericana de Bioinformatica
          organization_url: http://congresos.nnb.unam.mx/TIB2017/
          title: Functional Genomics and Transcriptomics Workshop
          url: ''
        - certificate_url: https://www.linkedin.com/in/mramos148 
          organization: See LinkedIn for more
          organization_url: https://www.linkedin.com/in/mramos148
          title: Additional Certificates
          url: https://www.linkedin.com/in/mramos148
          date_start: '2017-01-01'
          date_end: ""
          description: ""
    design:
      columns: '2'
  - block: collection
    content:
      title: Recent Publications
      text: |-
        {{% callout note %}}
        Quickly discover relevant content by [filtering publications](./publication/).
        {{% /callout %}}
      filters:
        folders:
          - publication
    design:
      columns: '2'
      view: citation
---
